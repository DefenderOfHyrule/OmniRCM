#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/usb/IOUSBLib.h>

NS_ASSUME_NONNULL_BEGIN

#define kTegraX1VendorID  0x0955u
#define kTegraX1ProductID 0x7321u

#define NXUSBDeviceInterface      IOUSBDeviceInterface245
#define kNXUSBDeviceInterfaceUUID kIOUSBDeviceInterfaceID245
#define NXUSBSubInterface         IOUSBInterfaceInterface245
#define kNXUSBSubInterfaceUUID    kIOUSBInterfaceInterfaceID245
#define NXCOMCall(OBJ, METHOD, ...) (*(OBJ))->METHOD((OBJ), ##__VA_ARGS__)

typedef NS_ENUM(NSInteger, RCMResultType) {
    RCMResultSuccess,
    RCMResultPatchedV1,
    RCMResultPatchedV2,
    RCMResultError,
};

@interface RCMResult : NSObject
@property (nonatomic, assign) RCMResultType type;
@property (nonatomic, copy, nullable) NSString *deviceId;
@property (nonatomic, copy, nullable) NSString *errorMessage;
+ (instancetype)success:(NSString *)deviceId;
+ (instancetype)patchedV1:(NSString *)deviceId;
+ (instancetype)patchedV2:(NSString *)deviceId;
+ (instancetype)error:(NSString *)message;
@end

@interface RCMInjector : NSObject

+ (RCMResult *)injectPayload:(NSData *)payloadData
                intermezzo:(NSData *)intermezzo
                    device:(NXUSBDeviceInterface * _Nonnull * _Nonnull)device
                   logBlock:(void (^)(NSString *line))logBlock;

@end

NS_ASSUME_NONNULL_END
