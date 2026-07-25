package io.github.omnircm.rcm

import android.content.Context
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import io.github.omnircm.OmniRcmApp
import io.github.omnircm.data.Payload
import java.nio.ByteBuffer
import java.nio.ByteOrder

object RcmInjector {

    const val VENDOR_ID  = 0x0955
    const val PRODUCT_ID = 0x7321
    private const val RCM_PAYLOAD_ADDR    = 0x40010000
    private const val INTERMEZZO_LOCATION = 0x4001F000
    private const val PAYLOAD_LOAD_BLOCK  = 0x40020000
    private const val MAX_LENGTH          = 0x30298
    private const val MARIKO_STOP_OFFSET  = 0x10000

    private var seenV1TimeoutAtF000 = false

    private const val EPIPE      = 32    // stall
    private const val ETIMEDOUT  = 110   // timeout: console stopped responding to writes
    private const val EREMOTEIO  = 121   // remote I/O error

    init { System.loadLibrary("rcm_injector") }
    private external fun nativeSmashStack(fd: Int, length: Int): Int

    private external fun nativeWriteBulk(fd: Int, epAddress: Int, data: ByteArray, length: Int, timeoutMs: Int): Int

    fun isRcmDevice(device: UsbDevice) =
        device.vendorId == VENDOR_ID && device.productId == PRODUCT_ID

    fun resetState() {
        seenV1TimeoutAtF000 = false
    }

    sealed class Result {
        data class Success(val deviceId: String) : Result()
        data class Error(val message: String) : Result()
        data class PatchedV1(val deviceId: String) : Result()
        data class PatchedV2(val deviceId: String) : Result()
    }

    fun inject(device: UsbDevice, payload: Payload, onLog: (String) -> Unit): Result {
        val userPayload = payload.file.readBytes()
        val sizeStr = String.format("%,d", userPayload.size)
        onLog("Loaded: ${payload.file.name} ($sizeStr bytes)")

        val intermezzo = OmniRcmApp.instance.assets.open("intermezzo.bin").readBytes()

        val buf = ByteBuffer.allocate(MAX_LENGTH)
        buf.order(ByteOrder.LITTLE_ENDIAN)
        buf.putInt(MAX_LENGTH)
        buf.put(ByteArray(676))
        var i = RCM_PAYLOAD_ADDR
        while (i < INTERMEZZO_LOCATION) { buf.putInt(INTERMEZZO_LOCATION); i += 4 }
        buf.put(intermezzo)
        buf.put(ByteArray(PAYLOAD_LOAD_BLOCK - INTERMEZZO_LOCATION - intermezzo.size))
        buf.put(userPayload)
        val unpaddedLen = buf.position()
        buf.position(0)

        val totalBlocks = (unpaddedLen + 0xFFF) / 0x1000
        onLog("Buffer built: ${totalBlocks * 0x1000} bytes in $totalBlocks blocks")
        onLog("Opening RCM device...")

        val usbManager = OmniRcmApp.instance.getSystemService(Context.USB_SERVICE) as UsbManager
        val connection = usbManager.openDevice(device)
            ?: return Result.Error("Could not open USB device. Permission granted?")
        val iface = device.getInterface(0)
        connection.claimInterface(iface, true)
        try {
            val epIn  = iface.getEndpoint(0)
            val epOut = iface.getEndpoint(1)

            val idBuf = ByteArray(16)
            val idRead = connection.bulkTransfer(epIn, idBuf, idBuf.size, 5000)
            if (idRead != idBuf.size)
                return Result.Error("Failed to read device ID (got $idRead bytes).")
            val idHex = idBuf.joinToString("") { "%02X".format(it) }
            onLog("Device ID: $idHex")

            if (idHex.endsWith("2101D0")) {
                onLog("\nThis device ID identifies as a Mariko (T214) console.")
                return Result.PatchedV2(idHex)
            }

            onLog("Sending payload ($totalBlocks blocks)...")

            val chunk = ByteArray(0x1000)
            var bytesSent = 0
            var lowBuffer = true
            while (bytesSent < unpaddedLen || lowBuffer) {
                buf.get(chunk)
                val sent = nativeWriteBulk(connection.fileDescriptor, epOut.address, chunk, chunk.size, 5000)
                if (sent != chunk.size) {
                    val errno = if (sent < 0) -sent else 0
                    val errDesc = when (errno) {
                        EPIPE     -> "EPIPE (stall)"
                        ETIMEDOUT -> "ETIMEDOUT (console stopped responding)"
                        EREMOTEIO -> "EREMOTEIO"
                        0         -> "short write ($sent of ${chunk.size} bytes)"
                        else      -> "errno $errno"
                    }
                    onLog("  Write failed at offset $bytesSent: $errDesc")

                    val isV1Signal = errno == EPIPE || errno == EREMOTEIO || (sent in 0 until chunk.size)
                    val isTimeout  = errno == ETIMEDOUT

                    return when {
                        isV1Signal                                                          -> Result.PatchedV1(idHex)
                        isTimeout && bytesSent == 0xF000                                    -> { seenV1TimeoutAtF000 = true;  Result.PatchedV1(idHex) }
                        isTimeout && bytesSent == MARIKO_STOP_OFFSET && seenV1TimeoutAtF000 -> Result.PatchedV1(idHex)
                        isTimeout && bytesSent == MARIKO_STOP_OFFSET                        -> {
                            if (idHex.endsWith("01101062")) Result.PatchedV1(idHex)
                            else Result.PatchedV2(idHex)
                        }
                        else                                                                -> Result.Error("Transfer failed at offset $bytesSent.")
                    }
                }
                if (bytesSent == 0xF000 && sent == chunk.size) seenV1TimeoutAtF000 = false
                lowBuffer = lowBuffer xor true
                bytesSent += 0x1000
            }

            onLog("Payload sent.")
            onLog("Smashing the stack...")
            val smashResult = nativeSmashStack(connection.fileDescriptor, 0x7000)
            return when (smashResult) {
                0    -> Result.Success(idHex)
                1    -> Result.PatchedV1(idHex)
                2    -> Result.PatchedV2(idHex)
                else -> Result.Error("Stack smash failed (code $smashResult).")
            }
        } finally {
            connection.releaseInterface(iface)
            connection.close()
        }
    }
}
