using System.Runtime.InteropServices;

namespace OmniRCM.Rcm;

internal static class LibUsb
{
    internal const string Lib = "libusb-omnircm";

    [DllImport(Lib, EntryPoint = "libusb_init")]
    public static extern int Init(ref IntPtr ctx);

    [DllImport(Lib, EntryPoint = "libusb_exit")]
    public static extern void Exit(IntPtr ctx);

    [DllImport(Lib, EntryPoint = "libusb_get_device_list")]
    public static extern nint GetDeviceList(IntPtr ctx, out IntPtr list);

    [DllImport(Lib, EntryPoint = "libusb_free_device_list")]
    public static extern void FreeDeviceList(IntPtr list, int unref_devices);

    [DllImport(Lib, EntryPoint = "libusb_get_bus_number")]
    public static extern byte GetBusNumber(IntPtr dev);

    [DllImport(Lib, EntryPoint = "libusb_get_device_address")]
    public static extern byte GetDeviceAddress(IntPtr dev);

    [DllImport(Lib, EntryPoint = "libusb_get_device_descriptor")]
    public static extern int GetDeviceDescriptor(IntPtr dev, out DeviceDescriptor desc);

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct DeviceDescriptor
    {
        public byte   bLength;
        public byte   bDescriptorType;
        public ushort bcdUSB;
        public byte   bDeviceClass;
        public byte   bDeviceSubClass;
        public byte   bDeviceProtocol;
        public byte   bMaxPacketSize0;
        public ushort idVendor;
        public ushort idProduct;
        public ushort bcdDevice;
        public byte   iManufacturer;
        public byte   iProduct;
        public byte   iSerialNumber;
        public byte   bNumConfigurations;
    }

    [DllImport(Lib, EntryPoint = "libusb_open")]
    public static extern int Open(IntPtr dev, out IntPtr handle);

    [DllImport(Lib, EntryPoint = "libusb_close")]
    public static extern void Close(IntPtr handle);

    [DllImport(Lib, EntryPoint = "libusb_set_auto_detach_kernel_driver")]
    public static extern int SetAutoDetachKernelDriver(IntPtr handle, int enable);

    [DllImport(Lib, EntryPoint = "libusb_set_configuration")]
    public static extern int SetConfiguration(IntPtr handle, int configuration);

    [DllImport(Lib, EntryPoint = "libusb_claim_interface")]
    public static extern int ClaimInterface(IntPtr handle, int interface_number);

    [DllImport(Lib, EntryPoint = "libusb_release_interface")]
    public static extern int ReleaseInterface(IntPtr handle, int interface_number);

    [DllImport(Lib, EntryPoint = "libusb_bulk_transfer")]
    public static extern int BulkTransfer(IntPtr handle, byte endpoint,
        byte[] data, int length, out int transferred, uint timeout);

    [DllImport(Lib, EntryPoint = "libusb_control_transfer")]
    public static extern int ControlTransfer(IntPtr handle,
        byte bmRequestType, byte bRequest,
        ushort wValue, ushort wIndex,
        IntPtr data, ushort wLength, uint timeout);

    public const int Success       =  0;
    public const int ErrorNoDevice = -4;
    public const int ErrorTimeout  = -7;

    [DllImport(Lib, EntryPoint = "libusb_error_name")]
    [return: MarshalAs(UnmanagedType.LPStr)]
    public static extern string ErrorName(int errcode);

    private static bool _resolverRegistered;
    private static readonly object _resolverLock = new();

    public static void RegisterResolver()
    {
        lock (_resolverLock)
        {
            if (_resolverRegistered) return;
            _resolverRegistered = true;
            NativeLibrary.SetDllImportResolver(typeof(LibUsb).Assembly, ResolveLibrary);
        }
    }

    private static IntPtr ResolveLibrary(string libraryName,
        System.Reflection.Assembly assembly, DllImportSearchPath? searchPath)
    {
        if (libraryName != Lib) return IntPtr.Zero;

        if (OperatingSystem.IsMacOS())
        {
            string[] candidates =
            [
                Path.Combine(AppContext.BaseDirectory, "libusb-omnircm.dylib"),
                "/opt/homebrew/lib/libusb-1.0.dylib",
                "/usr/local/lib/libusb-1.0.dylib",
                "/opt/local/lib/libusb-1.0.dylib",
                "libusb-1.0.dylib",
                "libusb-1.0",
            ];
            foreach (var c in candidates)
                if (NativeLibrary.TryLoad(c, assembly, searchPath, out var h)) return h;
        }
        else if (OperatingSystem.IsLinux())
        {
            string[] fallbacks =
            [
                "libusb-1.0.so.0",
                "libusb-1.0.so",
                "libusb-1.0",
            ];
            foreach (var c in fallbacks)
                if (NativeLibrary.TryLoad(c, assembly, searchPath, out var h)) return h;
        }

        return IntPtr.Zero;
    }
}
