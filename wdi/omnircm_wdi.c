#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <setupapi.h>
#include "libwdi.h"

typedef BOOL (WINAPI *PFN_UpdateDriver)(HWND, LPCSTR, LPCSTR, DWORD, PBOOL);
typedef BOOL (WINAPI *PFN_SetupCopyOEMInf)(PCSTR, PCSTR, DWORD, DWORD, PSTR, DWORD, PDWORD, PSTR*);

#define APX_VID           0x0955
#define APX_PID           0x7321
#define APX_DESC          "NVIDIA APX"
#define INF_NAME          "omnircm_apx.inf"
#define INSTALLFLAG_FORCE 0x00000001

static void enable_load_driver_privilege(void)
{
    HANDLE hToken = NULL;
    if (!OpenProcessToken(GetCurrentProcess(),
                          TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken))
        return;
    TOKEN_PRIVILEGES tp;
    LookupPrivilegeValueA(NULL, "SeLoadDriverPrivilege",
                          &tp.Privileges[0].Luid);
    tp.PrivilegeCount = 1;
    tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
    AdjustTokenPrivileges(hToken, FALSE, &tp, 0, NULL, NULL);
    CloseHandle(hToken);
}

static void remove_dir(const char *path)
{
    char pattern[MAX_PATH];
    _snprintf_s(pattern, MAX_PATH, _TRUNCATE, "%s\\*", path);

    WIN32_FIND_DATAA ffd;
    HANDLE h = FindFirstFileA(pattern, &ffd);
    if (h == INVALID_HANDLE_VALUE) return;
    do {
        if (!strcmp(ffd.cFileName, ".") || !strcmp(ffd.cFileName, ".."))
            continue;
        char child[MAX_PATH];
        _snprintf_s(child, MAX_PATH, _TRUNCATE, "%s\\%s", path, ffd.cFileName);
        if (ffd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
            remove_dir(child);
        else
            DeleteFileA(child);
    } while (FindNextFileA(h, &ffd));
    FindClose(h);
    RemoveDirectoryA(path);
}

__declspec(dllexport) int __stdcall OmniRcmInstallDriver(HWND hwnd)
{
    HMODULE hNewdev = LoadLibraryA("newdev.dll");
    if (!hNewdev) return WDI_ERROR_NOT_FOUND;

    PFN_UpdateDriver pfnUpdateDriver =
        (PFN_UpdateDriver)GetProcAddress(hNewdev, "UpdateDriverForPlugAndPlayDevicesA");
    if (!pfnUpdateDriver) {
        FreeLibrary(hNewdev);
        return WDI_ERROR_NOT_FOUND;
    }

    HMODULE hSetupapi = LoadLibraryA("setupapi.dll");
    PFN_SetupCopyOEMInf pfnCopyInf = hSetupapi
        ? (PFN_SetupCopyOEMInf)GetProcAddress(hSetupapi, "SetupCopyOEMInfA")
        : NULL;

    struct wdi_options_create_list ocl = {
        .list_all = TRUE, .list_hubs = FALSE, .trim_whitespaces = TRUE,
    };
    struct wdi_device_info *list = NULL;
    struct wdi_device_info *found = NULL;

    if (wdi_create_list(&list, &ocl) == WDI_SUCCESS) {
        for (struct wdi_device_info *d = list; d != NULL; d = d->next) {
            if (d->vid == APX_VID && d->pid == APX_PID) {
                found = d;
                break;
            }
        }
    }

    struct wdi_device_info static_dev = {
        .vid = APX_VID, .pid = APX_PID, .desc = APX_DESC,
    };
    struct wdi_device_info *dev = found ? found : &static_dev;

    struct wdi_options_prepare_driver opd = {
        .driver_type     = WDI_LIBUSBK,
        .disable_cat     = FALSE,
        .disable_signing = FALSE,
    };

    char drv_dir[MAX_PATH];
    strncpy_s(drv_dir, MAX_PATH, "C:\\omnircm_drv", _TRUNCATE);

    int r = wdi_prepare_driver(dev, drv_dir, INF_NAME, &opd);
    if (r != WDI_SUCCESS) {
        if (list) wdi_destroy_list(list);
        FreeLibrary(hNewdev);
        if (hSetupapi) FreeLibrary(hSetupapi);
        return r;
    }

    char inf_path[MAX_PATH];
    _snprintf_s(inf_path, MAX_PATH, _TRUNCATE, "%s\\%s", drv_dir, INF_NAME);

    if (GetFileAttributesA(inf_path) == INVALID_FILE_ATTRIBUTES) {
        if (list) wdi_destroy_list(list);
        FreeLibrary(hNewdev);
        if (hSetupapi) FreeLibrary(hSetupapi);
        return WDI_ERROR_NOT_FOUND;
    }

    struct wdi_options_install_cert oic = { .hWnd = NULL, .disable_warning = TRUE };
    wdi_install_trusted_certificate("libusbK.cat", &oic);

    enable_load_driver_privilege();

    const char *hw_id = (dev->hardware_id && dev->hardware_id[0])
        ? dev->hardware_id
        : "USB\\VID_0955&PID_7321";

    BOOL reboot = FALSE;
    BOOL ok = pfnUpdateDriver(NULL, hw_id, inf_path, INSTALLFLAG_FORCE, &reboot);
    DWORD err = GetLastError();

    int ret;
    if (ok) {
        if (pfnCopyInf) {
            char dest[MAX_PATH];
            pfnCopyInf(inf_path, NULL, 4, 0, dest, MAX_PATH, NULL, NULL);
        }
        ret = WDI_SUCCESS;
    } else {
        switch (err) {
            case ERROR_ACCESS_DENIED:  ret = WDI_ERROR_ACCESS;    break;
            case ERROR_NO_MORE_ITEMS:  ret = WDI_ERROR_NOT_FOUND; break;
            case ERROR_FILE_NOT_FOUND: ret = WDI_ERROR_NOT_FOUND; break;
            default:                   ret = WDI_ERROR_OTHER;      break;
        }
    }

    remove_dir(drv_dir);

    if (list) wdi_destroy_list(list);
    FreeLibrary(hNewdev);
    if (hSetupapi) FreeLibrary(hSetupapi);
    return ret;
}

__declspec(dllexport) int __stdcall OmniRcmIsDriverInstalled(void)
{
    struct wdi_device_info *list = NULL;
    struct wdi_options_create_list ocl = {
        .list_all = TRUE, .list_hubs = FALSE, .trim_whitespaces = TRUE,
    };
    if (wdi_create_list(&list, &ocl) != WDI_SUCCESS) return 0;

    int found = 0;
    for (struct wdi_device_info *d = list; d != NULL; d = d->next) {
        if (d->vid == APX_VID && d->pid == APX_PID) {
            if (d->driver &&
                (strstr(d->driver, "libusbK") || strstr(d->driver, "libusbk")))
                found = 1;
            break;
        }
    }
    wdi_destroy_list(list);
    return found;
}
