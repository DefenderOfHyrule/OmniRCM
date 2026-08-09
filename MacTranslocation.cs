#if MACOS
using System.Runtime.InteropServices;

namespace OmniRCM;

internal static class MacTranslocation
{
    private const string SecurityLib = "/System/Library/Frameworks/Security.framework/Security";
    private const string CoreFoundationLib = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";

    [DllImport(CoreFoundationLib)]
    private static extern IntPtr CFURLCreateFromFileSystemRepresentation(
        IntPtr allocator, byte[] buffer, long bufLen, [MarshalAs(UnmanagedType.I1)] bool isDirectory);

    [DllImport(CoreFoundationLib)]
    [return: MarshalAs(UnmanagedType.I1)]
    private static extern bool CFURLGetFileSystemRepresentation(
        IntPtr url, [MarshalAs(UnmanagedType.I1)] bool resolveAgainstBase, byte[] buffer, long maxBufLen);

    [DllImport(CoreFoundationLib)]
    private static extern void CFRelease(IntPtr cf);

    [DllImport(SecurityLib)]
    [return: MarshalAs(UnmanagedType.I1)]
    private static extern bool SecTranslocateIsTranslocatedURL(
        IntPtr path, [MarshalAs(UnmanagedType.I1)] out bool isTranslocated, out IntPtr error);

    [DllImport(SecurityLib)]
    private static extern IntPtr SecTranslocateCreateOriginalPathForURL(
        IntPtr translocatedPath, out IntPtr error);

    public static string? ResolveOriginalPath(string path)
    {
        IntPtr url = IntPtr.Zero;
        IntPtr originalUrl = IntPtr.Zero;
        IntPtr err = IntPtr.Zero;

        try
        {
            byte[] utf8 = System.Text.Encoding.UTF8.GetBytes(path);
            url = CFURLCreateFromFileSystemRepresentation(IntPtr.Zero, utf8, utf8.Length, true);
            if (url == IntPtr.Zero) return null;

            bool ok = SecTranslocateIsTranslocatedURL(url, out bool isTranslocated, out err);
            if (err != IntPtr.Zero) { CFRelease(err); err = IntPtr.Zero; }
            if (!ok || !isTranslocated) return null;

            originalUrl = SecTranslocateCreateOriginalPathForURL(url, out err);
            if (err != IntPtr.Zero) { CFRelease(err); err = IntPtr.Zero; }
            if (originalUrl == IntPtr.Zero) return null;

            byte[] buffer = new byte[4096];
            if (!CFURLGetFileSystemRepresentation(originalUrl, true, buffer, buffer.Length))
                return null;

            int len = Array.IndexOf(buffer, (byte)0);
            if (len < 0) len = buffer.Length;
            return System.Text.Encoding.UTF8.GetString(buffer, 0, len);
        }
        catch
        {
            return null;
        }
        finally
        {
            if (url != IntPtr.Zero) CFRelease(url);
            if (originalUrl != IntPtr.Zero) CFRelease(originalUrl);
        }
    }
}
#endif
