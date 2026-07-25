package io.github.omnircm.rcm

import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import io.github.omnircm.ui.MainActivity

class UsbReceiverActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.action == UsbManager.ACTION_USB_DEVICE_ATTACHED) {
            val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
            if (device != null && RcmInjector.isRcmDevice(device)) {
                val main = Intent(this, MainActivity::class.java).apply {
                    action = MainActivity.ACTION_USB_INJECT
                    putExtra(UsbManager.EXTRA_DEVICE, device)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                startActivity(main)
            }
        }
        finish()
    }
}
