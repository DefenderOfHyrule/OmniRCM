#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>

NS_ASSUME_NONNULL_BEGIN

#define NXUSBDeviceInterface IOUSBDeviceInterface245
#define kNXUSBDeviceInterfaceUUID kIOUSBDeviceInterfaceID245

@class RCMDeviceWatcher;

@protocol RCMDeviceWatcherDelegate <NSObject>
- (void)deviceWatcher:(RCMDeviceWatcher *)watcher deviceConnected:(NXUSBDeviceInterface * _Nonnull * _Nonnull)device;
- (void)deviceWatcher:(RCMDeviceWatcher *)watcher deviceDisconnected:(NXUSBDeviceInterface * _Nullable * _Nullable)device;
- (void)deviceWatcher:(RCMDeviceWatcher *)watcher error:(NSString *)message;
@end

@interface RCMDeviceWatcher : NSObject {
@public
    NXUSBDeviceInterface **_currentDevice;
    io_object_t _currentNotification;
}

@property (nonatomic, weak, nullable) id<RCMDeviceWatcherDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL deviceConnected;

- (void)start;
- (void)stop;

- (void)clearCurrentDevice;

@end

NS_ASSUME_NONNULL_END
