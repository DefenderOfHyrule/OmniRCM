using System.Runtime.InteropServices;

namespace OmniRCM.Rcm;

public enum SmashResult
{
    Success,
    PatchedV1,
    TimedOut,
    Error,
}

public sealed class RcmDevice : IDisposable
{
    public const int VendorId  = 0x0955;
    public const int ProductId = 0x7321;

    private const byte EpOut = 0x01;
    private const byte EpIn  = 0x81;

    private int _currentBuffer;

#if WINDOWS

    private IntPtr _usbHandle = IntPtr.Zero;

    private RcmDevice() { }

    public static bool IsPresent()
    {
        try
        {
            if (!LibUsbK.LstK_Init(out IntPtr list, 0)) return false;
            try { return LibUsbK.LstK_FindByVidPid(list, VendorId, ProductId, out _); }
            finally { LibUsbK.LstK_Free(list); }
        }
        catch { return false; }
    }

    public static (RcmDevice? Device, string? Error) TryOpenWithDiag()
    {
        try
        {
            if (!LibUsbK.LstK_Init(out IntPtr list, 0))
                return (null, $"USB enumeration failed (error {Marshal.GetLastWin32Error()})");

            bool found;
            IntPtr devInfo;
            try { found = LibUsbK.LstK_FindByVidPid(list, VendorId, ProductId, out devInfo); }
            finally { LibUsbK.LstK_Free(list); }

            if (!found || devInfo == IntPtr.Zero)
                return (null, null);

            if (!LibUsbK.UsbK_Init(out IntPtr handle, devInfo))
                return (null,
                    "Device found but could not be opened.\n" +
                    "OmniRCM requires the libusbK driver (not WinUSB).\n" +
                    "Run Zadig, select the APX device, choose libusbK, and click Install.");

            return (new RcmDevice { _usbHandle = handle }, null);
        }
        catch (DllNotFoundException)
        {
            return (null,
                "libusbK.dll not found.\n" +
                "Install the libusbK driver via Zadig (select libusbK, not WinUSB).");
        }
        catch (Exception ex)
        {
            return (null, $"USB open error: {ex.Message}");
        }
    }

    public static RcmDevice? TryOpen() => TryOpenWithDiag().Device;

    public byte[]? ReadBytes(int length)
    {
        byte[] buf = new byte[length];
        if (!LibUsbK.UsbK_ReadPipe(_usbHandle, EpIn, buf, (uint)length, out uint got, IntPtr.Zero))
            return null;
        return (int)got == length ? buf : null;
    }

    public int WriteSingleBlockResult(byte[] block, Action<string>? log = null)
    {
        _currentBuffer = 1 - _currentBuffer;
        if (!LibUsbK.UsbK_WritePipe(_usbHandle, EpOut, block, (uint)block.Length, out uint sent, IntPtr.Zero))
        {
            uint err = (uint)Marshal.GetLastWin32Error();
            log?.Invoke($"WriteBlock: UsbK_WritePipe failed error={err}");
            return err == 121 ? -2 : -1;
        }
        return (int)sent;
    }

    public bool WriteBlock(byte[] block) => WriteSingleBlockResult(block) >= 0;

    public bool SetWriteTimeout(uint ms)
    {
        const uint PIPE_TRANSFER_TIMEOUT = 0x03;
        return LibUsbK.UsbK_SetPipePolicy(_usbHandle, EpOut, PIPE_TRANSFER_TIMEOUT,
            sizeof(uint), ref ms);
    }

    public bool SwitchToHighBuffer()
    {
        if (_currentBuffer == 1) return true;
        return WriteSingleBlockResult(new byte[0x1000]) >= 0;
    }

    public SmashResult SmashStack(Action<string> log, CancellationToken ct)
    {
        uint size = (uint)IntPtr.Size;
        byte[] handleBytes = new byte[IntPtr.Size];
        if (!LibUsbK.UsbK_GetProperty(_usbHandle, 0,
                ref size, handleBytes, out uint _))
        {
            log($"Smash: UsbK_GetProperty failed (error {Marshal.GetLastWin32Error()})");
            return SmashResult.Error;
        }
        IntPtr masterHandle = (IntPtr.Size == 8)
            ? (IntPtr)BitConverter.ToInt64(handleBytes, 0)
            : (IntPtr)BitConverter.ToInt32(handleBytes, 0);

        if (masterHandle == IntPtr.Zero || masterHandle == new IntPtr(-1))
        {
            log("Smash: could not get raw device handle");
            return SmashResult.Error;
        }

        const int ReqSize = 24;
        byte[] req = new byte[ReqSize];
        BitConverter.TryWriteBytes(req.AsSpan(0), (uint)1000);
        BitConverter.TryWriteBytes(req.AsSpan(4), (uint)2);

        const int SmashLen = 0x7000;
        byte[] smashBuf = new byte[SmashLen];

        const uint IOCTL                    = 0x0022201CU;
        const uint ERROR_SEM_TIMEOUT        = 121;
        const uint ERROR_GEN_FAILURE        = 31;
        const uint ERROR_DEVICE_NOT_CONNECTED = 1167;

        bool result = LibUsbK.DeviceIoControl(masterHandle, IOCTL,
            req, (uint)ReqSize,
            smashBuf, (uint)SmashLen,
            out uint _, IntPtr.Zero);

        if (!result)
        {
            uint err = (uint)Marshal.GetLastWin32Error();
            log($"Smash: DeviceIoControl status error={err}");
            if (err == ERROR_SEM_TIMEOUT)
                return SmashResult.Success;
            if (err == ERROR_GEN_FAILURE || err == ERROR_DEVICE_NOT_CONNECTED)
                return SmashResult.TimedOut;
            return SmashResult.Error;
        }
        return SmashResult.PatchedV1;
    }

    public void Dispose()
    {
        if (_usbHandle != IntPtr.Zero)
        {
            LibUsbK.UsbK_Free(_usbHandle);
            _usbHandle = IntPtr.Zero;
        }
    }
#else
    private IntPtr _ctx    = IntPtr.Zero;
    private IntPtr _handle = IntPtr.Zero;
    private byte   _busNumber;
    private byte   _devAddress;

    private RcmDevice() { }

    public static bool IsPresent()
    {
        LibUsb.RegisterResolver();
        IntPtr ctx = IntPtr.Zero;
        try
        {
            if (LibUsb.Init(ref ctx) != LibUsb.Success) return false;
            nint count = LibUsb.GetDeviceList(ctx, out IntPtr list);
            bool found = false;
            try
            {
                for (int i = 0; i < count; i++)
                {
                    IntPtr dev = Marshal.ReadIntPtr(list, i * IntPtr.Size);
                    if (dev == IntPtr.Zero) break;
                    if (LibUsb.GetDeviceDescriptor(dev, out var desc) != LibUsb.Success) continue;
                    if (desc.idVendor == VendorId && desc.idProduct == ProductId) { found = true; break; }
                }
            }
            finally { LibUsb.FreeDeviceList(list, 1); }
            return found;
        }
        catch { return false; }
        finally { if (ctx != IntPtr.Zero) LibUsb.Exit(ctx); }
    }

    public static (RcmDevice? Device, string? Error) TryOpenWithDiag()
        => (TryOpen(), null);

    public static RcmDevice? TryOpen()
    {
        LibUsb.RegisterResolver();
        IntPtr ctx    = IntPtr.Zero;
        IntPtr handle = IntPtr.Zero;
        bool   inited = false;
        try
        {
            if (LibUsb.Init(ref ctx) != LibUsb.Success) return null;
            inited = true;

            nint count = LibUsb.GetDeviceList(ctx, out IntPtr list);
            if (count <= 0) { LibUsb.FreeDeviceList(list, 1); return null; }

            IntPtr target = IntPtr.Zero;
            byte   bus = 0, addr = 0;
            try
            {
                for (int i = 0; i < count; i++)
                {
                    IntPtr dev = Marshal.ReadIntPtr(list, i * IntPtr.Size);
                    if (dev == IntPtr.Zero) break;
                    if (LibUsb.GetDeviceDescriptor(dev, out var desc) != LibUsb.Success) continue;
                    if (desc.idVendor != VendorId || desc.idProduct != ProductId) continue;
                    target = dev;
                    bus    = LibUsb.GetBusNumber(dev);
                    addr   = LibUsb.GetDeviceAddress(dev);
                    break;
                }
            }
            finally { LibUsb.FreeDeviceList(list, 1); }

            if (target == IntPtr.Zero) goto cleanup;
            if (LibUsb.Open(target, out handle) != LibUsb.Success) goto cleanup;

            if (LibUsb.ClaimInterface(handle, 0) != LibUsb.Success) goto closeHandle;

            return new RcmDevice { _ctx = ctx, _handle = handle, _busNumber = bus, _devAddress = addr };

            closeHandle: LibUsb.Close(handle);
            cleanup:     LibUsb.Exit(ctx);
            return null;
        }
        catch
        {
            if (handle != IntPtr.Zero) LibUsb.Close(handle);
            if (inited) LibUsb.Exit(ctx);
            return null;
        }
    }

    public byte[]? ReadBytes(int length)
    {
        byte[] buf = new byte[length];
        int rc = LibUsb.BulkTransfer(_handle, EpIn, buf, length, out int got, 5000);
        return rc == LibUsb.Success && got == length ? buf : null;
    }

    public int WriteSingleBlockResult(byte[] block, Action<string>? log = null)
    {
        _currentBuffer = 1 - _currentBuffer;
        int rc = LibUsb.BulkTransfer(_handle, EpOut, block, block.Length, out int sent, 5000);
        if (rc == LibUsb.Success) return sent;
        log?.Invoke($"WriteBlock: libusb_bulk_transfer rc={rc}");
        if (rc == LibUsb.ErrorNoDevice) return -2;
        return -1;
    }

    public bool WriteBlock(byte[] block) => WriteSingleBlockResult(block) >= 0;

    public bool SetWriteTimeout(uint ms) => true;

    public bool SwitchToHighBuffer()
    {
        if (_currentBuffer == 1) return true;
        return WriteSingleBlockResult(new byte[0x1000]) >= 0;
    }

    public SmashResult SmashStack(Action<string> log, CancellationToken ct)
    {
        if (OperatingSystem.IsLinux())
            return SmashStackLinux(log);
        return SmashStackMacOs(log, ct);
    }

    private SmashResult SmashStackMacOs(Action<string> log, CancellationToken ct)
    {
        const int  SmashLen       = 0x7000;
        const uint SmashTimeoutMs = 500;
        byte[]     buf            = new byte[SmashLen];
        var        pin            = GCHandle.Alloc(buf, GCHandleType.Pinned);

        int rc;
        try
        {
            rc = LibUsb.ControlTransfer(_handle,
                0x82, 0x00, 0, 0,
                pin.AddrOfPinnedObject(), (ushort)SmashLen, SmashTimeoutMs);
        }
        finally { pin.Free(); }

        if (rc >= 0)                    return SmashResult.PatchedV1;
        if (rc == -9)                   return SmashResult.PatchedV1;
        if (rc == LibUsb.ErrorTimeout)  return SmashResult.Success;
        if (rc == -4)                   return SmashResult.TimedOut;
        return SmashResult.Success;
    }

    private SmashResult SmashStackLinux(Action<string> log)
    {
        string path = $"/dev/bus/usb/{_busNumber:D3}/{_devAddress:D3}";
        int fd = Libc.Open(path, Libc.O_RDWR);
        if (fd < 0)
        {
            log($"Smash: could not open {path} (errno={Marshal.GetLastWin32Error()})");
            return SmashResult.Error;
        }
        try   { return Libc.SubmitSmashUrb(fd, log); }
        finally { Libc.Close(fd); }
    }

    public void Dispose()
    {
        if (_handle != IntPtr.Zero)
        {
            LibUsb.ReleaseInterface(_handle, 0);
            LibUsb.Close(_handle);
            _handle = IntPtr.Zero;
        }
        if (_ctx != IntPtr.Zero)
        {
            LibUsb.Exit(_ctx);
            _ctx = IntPtr.Zero;
        }
    }
#endif
}

#if !WINDOWS
internal static class Libc
{
    private const string LibName = "libc";

    public const int O_RDWR  = 2;
    private const int EAGAIN     = 11;
    private const int ENOENT     = 2;
    private const int ENODEV     = 19;
    private const int EPIPE      = 32;
    private const int EREMOTEIO  = 121;
    private const int ECONNRESET = 104;

    [DllImport(LibName, EntryPoint = "open",   SetLastError = true)]
    public static extern int Open([MarshalAs(UnmanagedType.LPStr)] string path, int flags);

    [DllImport(LibName, EntryPoint = "close",  SetLastError = true)]
    public static extern int Close(int fd);

    [DllImport(LibName, EntryPoint = "ioctl",  SetLastError = true)]
    private static extern int Ioctl(int fd, ulong request, IntPtr arg);

    [DllImport(LibName, EntryPoint = "usleep")]
    private static extern int Usleep(uint useconds);

    private const ulong SUBMITURB     = 0x8038550AUL;
    private const ulong DISCARDURB    = 0x0000550BUL;
    private const ulong REAPURBNDELAY = 0x4008550DUL;

    private const int URB_SIZE             = 56;
    private const int URB_OFF_TYPE         = 0;
    private const int URB_OFF_ENDPOINT     = 1;
    private const int URB_OFF_STATUS       = 4;
    private const int URB_OFF_FLAGS        = 8;
    private const int URB_OFF_BUFFER       = 16;
    private const int URB_OFF_BUFFER_LEN   = 24;

    private const uint USBDEVFS_URB_SHORT_NOT_OK = 0x01;

    private const int CTRL_SIZE            = 8;

    private const byte USBDEVFS_URB_TYPE_CONTROL = 2;
    private const byte USB_DIR_IN                = 0x80;

    public static SmashResult SubmitSmashUrb(int fd, Action<string> log)
    {
        const int SmashLen    = 0x7000;
        int       totalBufLen = CTRL_SIZE + SmashLen;

        IntPtr dataBuf = Marshal.AllocHGlobal(totalBufLen);
        IntPtr urbBuf  = Marshal.AllocHGlobal(URB_SIZE);
        IntPtr reapBuf = Marshal.AllocHGlobal(IntPtr.Size);

        try
        {
            for (int i = 0; i < totalBufLen; i++) Marshal.WriteByte(dataBuf, i, 0);
            for (int i = 0; i < URB_SIZE;     i++) Marshal.WriteByte(urbBuf,  i, 0);
            Marshal.WriteIntPtr(reapBuf, IntPtr.Zero);

            Marshal.WriteByte(dataBuf,  0, 0x82);
            Marshal.WriteByte(dataBuf,  1, 0x00);
            Marshal.WriteInt16(dataBuf, 2, 0);
            Marshal.WriteInt16(dataBuf, 4, 0);
            Marshal.WriteInt16(dataBuf, 6, (short)(ushort)SmashLen);

            Marshal.WriteByte(urbBuf,   URB_OFF_TYPE,       USBDEVFS_URB_TYPE_CONTROL);
            Marshal.WriteByte(urbBuf,   URB_OFF_ENDPOINT,   USB_DIR_IN);
            Marshal.WriteInt32(urbBuf,  URB_OFF_FLAGS,      (int)USBDEVFS_URB_SHORT_NOT_OK);
            Marshal.WriteIntPtr(urbBuf, URB_OFF_BUFFER,     dataBuf);
            Marshal.WriteInt32(urbBuf,  URB_OFF_BUFFER_LEN, totalBufLen);

            int rc = Ioctl(fd, SUBMITURB, urbBuf);
            if (rc != 0)
            {
                log($"Smash: SUBMITURB ioctl failed (rc={rc} errno={Marshal.GetLastWin32Error()})");
                return SmashResult.Error;
            }

            Usleep(250_000);

            rc = Ioctl(fd, REAPURBNDELAY, reapBuf);
            if (rc < 0)
            {
                int errno = Marshal.GetLastWin32Error();
                if (errno == EAGAIN)
                {
                    int discardRc = Ioctl(fd, DISCARDURB, urbBuf);
                    if (discardRc != 0)
                        log($"Smash: DISCARDURB ioctl failed (rc={discardRc} errno={Marshal.GetLastWin32Error()})");
                    Usleep(40_000);
                    rc = Ioctl(fd, REAPURBNDELAY, reapBuf);
                    if (rc < 0)
                    {
                        int errno2 = Marshal.GetLastWin32Error();
                        if (errno2 == ENODEV)
                            return SmashResult.TimedOut;
                        log($"Smash: URB still pending after discard (errno={errno2})");
                        return SmashResult.Error;
                    }
                    int urbStatus2 = Marshal.ReadInt32(urbBuf, URB_OFF_STATUS);
                    int actualLen2 = Marshal.ReadInt32(urbBuf, 28);
                    log($"Smash: post discard status={urbStatus2} actualLen={actualLen2}");
                    if (urbStatus2 == 0 && actualLen2 == 2)
                        return SmashResult.PatchedV1;
                    if (urbStatus2 == -EPIPE)
                        return SmashResult.PatchedV1;
                    if (urbStatus2 == -EREMOTEIO)
                        return SmashResult.PatchedV1;
                    if (urbStatus2 == -ECONNRESET || urbStatus2 == -ENOENT)
                        return SmashResult.Success;
                    log($"Smash: unrecognized post discard status={urbStatus2} actualLen={actualLen2}");
                    return SmashResult.Error;
                }
                else if (errno == ENODEV)
                {
                    return SmashResult.TimedOut;
                }
                else
                {
                    log($"Smash: unexpected REAPURBNDELAY result (rc={rc} errno={errno})");
                    return SmashResult.Error;
                }
            }
            else
            {
                int urbStatus = Marshal.ReadInt32(urbBuf, URB_OFF_STATUS);
                int actualLen = Marshal.ReadInt32(urbBuf, 28);
                log($"Smash: fast path status={urbStatus} actualLen={actualLen}");
                if (urbStatus == 0 && actualLen == 2)
                    return SmashResult.PatchedV1;
                if (urbStatus == -EPIPE)
                    return SmashResult.PatchedV1;
                if (urbStatus == -EREMOTEIO)
                    return SmashResult.PatchedV1;
            }

            return SmashResult.Success;
        }
        finally
        {
            Marshal.FreeHGlobal(dataBuf);
            Marshal.FreeHGlobal(urbBuf);
            Marshal.FreeHGlobal(reapBuf);
        }
    }
}
#endif

#if WINDOWS
internal static class LibUsbK
{
    private const string Lib = "libusbK";

    public const int KLST_DEVINFO_DRIVERID_OFFSET = 0;
    public const int KUSB_DRVID_LIBUSBK = 2;

    [DllImport(Lib, SetLastError = true)]
    public static extern bool LstK_Init(out IntPtr DeviceList, int Flags);

    [DllImport(Lib, SetLastError = true)]
    public static extern bool LstK_Free(IntPtr DeviceList);

    [DllImport(Lib, SetLastError = true)]
    public static extern bool LstK_FindByVidPid(IntPtr DeviceList, int Vid, int Pid,
        out IntPtr DeviceInfo);

    [DllImport(Lib, SetLastError = true)]
    public static extern bool UsbK_Init(out IntPtr InterfaceHandle, IntPtr DevInfo);

    [DllImport(Lib, SetLastError = true)]
    public static extern bool UsbK_Free(IntPtr InterfaceHandle);

    [DllImport(Lib, SetLastError = true)]
    public static extern bool UsbK_ReadPipe(IntPtr InterfaceHandle, byte PipeID,
        byte[] Buffer, uint BufferLength, out uint LengthTransferred, IntPtr Overlapped);

    [DllImport(Lib, SetLastError = true)]
    public static extern bool UsbK_WritePipe(IntPtr InterfaceHandle, byte PipeID,
        byte[] Buffer, uint BufferLength, out uint LengthTransferred, IntPtr Overlapped);

    [DllImport(Lib, SetLastError = true)]
    public static extern bool UsbK_GetProperty(IntPtr InterfaceHandle, int PropertyType,
        ref uint PropertySize, byte[] Value, out uint LengthTransferred);

    [DllImport(Lib, SetLastError = true)]
    public static extern bool UsbK_SetPipePolicy(IntPtr InterfaceHandle, byte PipeID,
        uint PolicyType, uint ValueLength, ref uint Value);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode,
        byte[] lpInBuffer, uint nInBufferSize,
        byte[] lpOutBuffer, uint nOutBufferSize,
        out uint lpBytesReturned, IntPtr lpOverlapped);
}
#endif
