# OmniRCM for Android

A native Android payload injector for the Nintendo Switch.

## Requirements

- Any device running Android 6+ (x86, x64, armv7, armv8)
- The ability to install APK's from external sources
- A micro USB to USB A OTG adapter (not needed if you use a phone with USB C port)
- A good quality USB A to C cable (or C to C if you use a phone with USB C port)

## How to use

Usage is simple:

1. Install the `app-debug.apk` from the [releases](https://github.com/DefenderOfHyrule/OmniRCM/releases/latest) page,
1. Open the app from your home menu,
1. [Put your switch in RCM](https://switch.hacks.guide/user_guide/rcm/entering_rcm),
1. Plug your Switch into your device via USB,
1. Allow OmniRCM to access the `APX` device (either temporarily or permanently),
1. Fetch provided remote payloads, or add your own custom payload (`.bin` file),
1. Click `Inject` and observe the injection result.

## Troubleshooting

For extra troubleshooting, you can also enable the Log at the top of the app. The Log contains slightly more information than the injection result, to provide assistance with figuring out the cause of an issue if present.

## Building from source

### Requirements

- A computer running Linux (Windows instructions may be added in the future)

### Instructions

1. Download the latest release of the "Command line tools only" package for Linux from https://developer.android.com/studio#command-tools (version number changes, so I can't provide a static link)
1. Clone the repository in a terminal window with `git clone --recurse-submodules https://github.com/DefenderOfHyrule/OmniRCM.git`,
1. `cd` into the cloned repository,
1. Run the following commands in a separate terminal window from the directory you've downloaded the command line tools package with (replace `*` with the version number of the package you've downloaded):
    ```
    mkdir -p ~/android-sdk/cmdline-tools
    unzip commandlinetools-linux-*.zip -d ~/android-sdk/cmdline-tools
    mv ~/android-sdk/cmdline-tools/cmdline-tools ~/android-sdk/cmdline-tools/latest
    ```
1. Point gradle at the SDK installation (same terminal window as the one you cloned the repository with):
    ```
    echo "sdk.dir=$HOME/android-sdk" > android/local.properties
    ```
1. Install the project dependencies:
    ```
    export PATH="$HOME/android-sdk/cmdline-tools/latest/bin:$PATH"
    yes | sdkmanager --licenses
    sdkmanager "platform-tools" "platforms;android-36" "build-tools;35.0.0" "ndk;28.2.13676358" "cmake;3.22.1"
    ```
1. `cd` into the `android` directory,
1. Run the following command from the `android` directory to start building the app:
    ```
    ./gradlew assembleDebug
    ```

The `app-debug.apk` release will be located in `app/build/outputs/apk/debug`
