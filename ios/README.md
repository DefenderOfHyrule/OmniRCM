# OmniRCM for iOS

A native iOS payload injector for the Nintendo Switch.

**Note:** A jailbroken device is mandatory for you to use this payload injector.

## Requirements

- A jailbroken device running iOS/iPadOS 9 or later
- A lightning to USB A OTG adapter (not needed if you use a jailbroken USB C iPhone/iPad)
- A good quality USB A to C cable (or C to C if you use a jailbroken USB C iPhone/iPad)

## How to use

Usage is simple:

1. Visit the [OmniRCM Sileo repository](https://omnircm.nintendohomebrew.com/repo/),
1. Press `Add to Sileo`,
1. Open the link in Sileo when prompted,
1. Add the repository,
1. Sync your sources,
1. Navigate to `OmniRCM` > `Utilities` > `OmniRCM`,
1. Press `GET`,
1. Install the app from the Sileo queue at the bottom right of your screen,
1. [Put your switch in RCM](https://switch.hacks.guide/user_guide/rcm/entering_rcm),
1. Plug your Switch into your device via USB,
1. Launch the OmniRCM app from your home menu,
1. Fetch provided remote payloads, or add your own custom payload (`.bin` file),
1. Click `Inject` and observe the injection result.

## Troubleshooting

For extra troubleshooting, you can also enable the Log at the top of the app. The Log contains slightly more information than the injection result, to provide assistance with figuring out the cause of an issue if present.

## Building from source

### Requirements

- [Theos](https://theos.dev/docs/installation)

Open a terminal window and run the following command from the `ios` directory:
```
make package
```

The release `.deb` will be located in the `packages` directory.
