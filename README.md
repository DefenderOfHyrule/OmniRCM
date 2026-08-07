<p align="center">
  <img alt="OmniRCM" src="Assets/icon.png">
</p>

# OmniRCM

**OmniRCM** is a self-contained .NET/Avalonia based payload injector for the Nintendo Switch that aims to support (nearly) all desktop- and mobile platforms. 

## Downloading OmniRCM

You can download the latest release of OmniRCM for your operating system from the [releases](https://github.com/DefenderOfHyrule/OmniRCM/releases/latest) page, refer to the table below for the platform-specific release naming scheme.

| Platform                              | Release name                                                           |
|---------------------------------------|------------------------------------------------------------------------|
| Windows x64                           | `OmniRCM-win-x64.exe`                                                  |
| Linux x64                             | `OmniRCM-linux-x64`                                                    |
| Linux arm64                           | `OmniRCM-linux-arm64`                                                  |
| macOS (x64, arm64)                    | `OmniRCM-osx.zip`                                                      |
| Android (x64, x86, armv7, armv8)      | `OmniRCM-android.apk`                                                  |
| iOS (release .deb, rootful/rootless)  | `OmniRCM-iOS-rootful.deb` or `OmniRCM-iOS-rootless.deb`                |
| iOS (Sileo)                           | [OmniRCM Sileo repository](https://omnircm.nintendohomebrew.com/repo/) |
| ChromeOS                              | [OmniRCM Web injector](https://omnircm.nintendohomebrew.com/web/)      |

## Using OmniRCM

Follow the [Platform-specific setup](#platform-specific-setup) below for your operating system. Once done, follow the instructions below:

1. Fetch provided remote payloads, or add your own custom payload (`.bin` file),
1. Click the `Inject Payload` button.

OmniRCM should now show the injection result.

## Platform-specific setup

### Windows

For Windows, you will need to install the libusbK driver for the APX device to be detected. To do this, follow the instructions below:

1. [Put your switch in RCM](https://switch.hacks.guide/user_guide/rcm/entering_rcm),
1. Plug your Switch into your PC via USB,
1. Open `OmniRCM-win-x64.exe`,
    > If you get a SmartScreen popup, click `More info` and click `Run anyway`. This popup happens because the app is unsigned, and I don't plan on giving Microsoft money to get the app signed :P.
1. Click the red `Install Driver` button near the top of the OmniRCM window,
1. Press `Yes` on the UAC (admin) prompt that appears. 

Once you've done this, you can continue with [Using OmniRCM](#using-omnircm).

### Linux (x64 & arm64)

For Linux, you will likely want to set up root-less payload injection. To do this, follow the instructions below:

1. [Put your switch in RCM](https://switch.hacks.guide/user_guide/rcm/entering_rcm),
1. Plug your Switch into your PC via USB,
1. Open `OmniRCM-linux-(architecture)`,
    > You'll need to make the executable executable if your file manager doesn't allow you to run the executable from your file manager directly. To do this, follow the instructions below:
    > 1. Open a terminal window,
    > 1. Enter the following command: `chmod +x /path/to/OmniRCM-linux-(architecture)` (replacing /path/to with the actual path to the executable).
    > 1. You should now be able to double click the app to open it from your file manager.
    > 1. **Note:** most file managers *do* allow you to make a file executable by right clicking the file and going to `Properties` > `Permissions` (or similar) > `Allow executing file as program`. The process is roughly the same for all Linux distributions.
1. Click the red `Setup udev` button near the top of the OmniRCM window,
1. Fill in your root password in the dialogue box that appears,
1. Click `Install`,
1. Log out and back in. On some distributions (notably, Fedora) require a full reboot for group membership to take effect.

Once you've done this, you can continue with [Using OmniRCM](#using-omnircm).

### macOS (x64 & arm64)

For macOS, 

1. [Put your switch in RCM](https://switch.hacks.guide/user_guide/rcm/entering_rcm),
1. Plug your Switch into your mac via USB,
1. Extract the `OmniRCM-osx.zip` archive somewhere (if needed, usually automatic),
1. Open `OmniRCM.app` from Finder.
    
Once you've done this, you can continue with [Using OmniRCM](#using-omnircm).

## Building from source

Requires .NET 10, run the command below in a terminal window from the root of the repository:
```bash
./build-releases.sh
```

Releases will be written to the `releases` folder in the root of the repository.

If you want to compile for Android or iOS, please refer to their README's: [Android](android/README.md) - [iOS](ios/README.md)
