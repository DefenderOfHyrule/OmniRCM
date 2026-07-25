#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RCMPayload : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSURL *fileURL;
@property (nonatomic, assign) BOOL isCustom;
@property (nonatomic, copy, nullable) NSString *version;
@property (nonatomic, assign) long long fileSize;
- (instancetype)initWithName:(NSString *)name fileURL:(NSURL *)url isCustom:(BOOL)custom version:(nullable NSString *)version;
@end

extern NSString *const PayloadManagerDidUpdateNotification;

@interface PayloadManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<RCMPayload *> *payloads;
@property (nonatomic, readonly, nullable) NSData *intermezzoData;

- (void)refresh;
- (void)fetchAllWithLog:(void (^)(NSString *line))logBlock completion:(void (^)(void))completion;
- (nullable RCMPayload *)addCustomPayloadFromURL:(NSURL *)sourceURL error:(NSError **)outError;
- (void)deletePayload:(RCMPayload *)payload;

@end

NS_ASSUME_NONNULL_END
