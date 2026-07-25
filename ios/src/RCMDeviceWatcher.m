#import "RCMDeviceWatcher.h"
#import "RCMInjector.h"
#import <IOKit/IOCFPlugIn.h>
#import <mach/mach.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wavailability"
extern const mach_port_t kIOMasterPortDefault __API_AVAILABLE(ios(1.0));
#pragma clang diagnostic pop

#define kIOMainPortDefault kIOMasterPortDefault

static void DeviceAdded(void *refCon, io_iterator_t iterator);
static void DeviceRemoved(void *refCon, io_service_t service, natural_t messageType, void *arg);

@interface RCMDeviceWatcher () {
    io_iterator_t _deviceIter;
}
@property (assign, nonatomic) IONotificationPortRef notifyPort;
@end

@implementation RCMDeviceWatcher

- (void)dealloc {
    [self stop];
}

- (void)start {
    kern_return_t kr;
    [self stop];

    NSMutableDictionary *matchingDict =
        (__bridge_transfer NSMutableDictionary *)IOServiceMatching("IOUSBHostDevice");
    if (!matchingDict) {
        NSLog(@"RCMDeviceWatcher: Could not create IOUSBHostDevice matching dict");
        [self.delegate deviceWatcher:self error:@"Could not create USB matching dict"];
        return;
    }
    [matchingDict setValue:@(kTegraX1VendorID)  forKey:@(kUSBVendorID)];
    [matchingDict setValue:@(kTegraX1ProductID) forKey:@(kUSBProductID)];

    self.notifyPort = IONotificationPortCreate(kIOMainPortDefault);
    if (!self.notifyPort) {
        NSLog(@"RCMDeviceWatcher: Could not create notification port");
        [self.delegate deviceWatcher:self error:@"Could not create IOKit notification port"];
        return;
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(),
                       IONotificationPortGetRunLoopSource(self.notifyPort),
                       kCFRunLoopDefaultMode);

    kr = IOServiceAddMatchingNotification(self.notifyPort,
                                          kIOFirstMatchNotification,
                                          (__bridge_retained CFDictionaryRef)matchingDict,
                                          DeviceAdded,
                                          (__bridge void *)self,
                                          &_deviceIter);
    if (kr) {
        NSLog(@"RCMDeviceWatcher: IOServiceAddMatchingNotification failed: 0x%08x", kr);
        [self.delegate deviceWatcher:self error:[NSString stringWithFormat:
            @"Could not register for USB notifications (0x%08x)", kr]];
        return;
    }

    NSLog(@"RCMDeviceWatcher: Listening for Tegra X1 (VID:%04x PID:%04x)",
          kTegraX1VendorID, kTegraX1ProductID);

    dispatch_async(dispatch_get_main_queue(), ^{
        [self handleDevicesAdded:self->_deviceIter];
        NSLog(@"RCMDeviceWatcher: Done processing initial device list");
    });
}

- (void)stop {
    [self clearCurrentDevice];
    if (self.notifyPort) {
        IONotificationPortDestroy(self.notifyPort);
        self.notifyPort = NULL;
    }
    if (_deviceIter) {
        IOObjectRelease(_deviceIter);
        _deviceIter = 0;
    }
    _deviceConnected = NO;
}

- (void)clearCurrentDevice {
    if (_currentNotification) {
        IOObjectRelease(_currentNotification);
        _currentNotification = 0;
    }

    _currentDevice = NULL;
}

#pragma mark - IOKit callbacks

- (void)handleDevicesAdded:(io_iterator_t)iterator {
    kern_return_t kr;
    io_service_t service;

    NSLog(@"RCMDeviceWatcher: Processing new devices");

    while ((service = IOIteratorNext(iterator))) {

        [self clearCurrentDevice];

        io_name_t ioName;
        kr = IORegistryEntryGetName(service, ioName);
        NSString *name = (kr == KERN_SUCCESS)
            ? [NSString stringWithCString:ioName encoding:NSASCIIStringEncoding]
            : @"(unknown)";
        NSLog(@"RCMDeviceWatcher: Device added: 0x%08x `%@'", service, name);

        IOCFPlugInInterface **plug = NULL;
        SInt32 score;
        kr = IOCreatePlugInInterfaceForService(service,
                                               kIOUSBDeviceUserClientTypeID,
                                               kIOCFPlugInInterfaceID,
                                               &plug, &score);
        if (kr || !plug) {
            NSLog(@"RCMDeviceWatcher: Could not create plugin interface: 0x%08x", kr);
            goto cleanup;
        }

        NXUSBDeviceInterface **dev = NULL;
        (*plug)->QueryInterface(plug,
                                CFUUIDGetUUIDBytes(kNXUSBDeviceInterfaceUUID),
                                (void **)&dev);
        NXCOMCall(plug, Release);
        plug = NULL;

        if (!dev) {
            NSLog(@"RCMDeviceWatcher: QueryInterface returned no interface");
            goto cleanup;
        }

        {
            io_object_t notification = 0;
            kr = IOServiceAddInterestNotification(self.notifyPort,
                                                  service,
                                                  kIOGeneralInterest,
                                                  DeviceRemoved,
                                                  (__bridge void *)self,
                                                  &notification);
            if (kr != KERN_SUCCESS) {
                NSLog(@"RCMDeviceWatcher: IOServiceAddInterestNotification failed: 0x%08x", kr);
            }
            _currentNotification = notification;
        }

        IOObjectRelease(service);

        _currentDevice = dev;
        _deviceConnected = YES;

        [self.delegate deviceWatcher:self deviceConnected:dev];
        return;

    cleanup:
        IOObjectRelease(service);
    }
}

- (void)handleDeviceRemoved {
    NSLog(@"RCMDeviceWatcher: Device removed");
    _deviceConnected = NO;

    NXUSBDeviceInterface **dev = _currentDevice;

    if (_currentNotification) {
        IOObjectRelease(_currentNotification);
        _currentNotification = 0;
    }
    _currentDevice = NULL;

    if (dev) {
        UInt32 loc;
        kern_return_t kr = NXCOMCall(dev, GetLocationID, &loc);
        if (kr != kIOReturnNoDevice && kr != kIOReturnNotOpen) {

            NXCOMCall(dev, Release);
        }
    }

    [self.delegate deviceWatcher:self deviceDisconnected:dev];
}

@end

static void DeviceAdded(void *refCon, io_iterator_t iterator) {
    RCMDeviceWatcher *watcher = (__bridge RCMDeviceWatcher *)refCon;
    [watcher handleDevicesAdded:iterator];
}

static void DeviceRemoved(void *refCon, io_service_t service, natural_t messageType, void *arg) {
    if (messageType == kIOMessageServiceIsTerminated) {
        RCMDeviceWatcher *watcher = (__bridge RCMDeviceWatcher *)refCon;
        [watcher handleDeviceRemoved];
    }
}
