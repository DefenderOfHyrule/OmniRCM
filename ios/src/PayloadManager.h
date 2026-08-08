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

@interface RCMCustomSource : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *repo;
@property (nonatomic, copy) NSString *assetMatch;
@property (nonatomic, assign) BOOL isZip;
@property (nonatomic, copy) NSString *zipInnerPattern;
@end

extern NSString *const PayloadManagerDidUpdateNotification;

@interface PayloadManager : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<RCMPayload *> *payloads;
@property (nonatomic, readonly) NSArray<RCMCustomSource *> *customSources;
@property (nonatomic, readonly, nullable) NSData *intermezzoData;

- (void)refresh;
- (void)fetchAllWithLog:(void (^)(NSString *line))logBlock completion:(void (^)(void))completion;
- (nullable RCMPayload *)addCustomPayloadFromURL:(NSURL *)sourceURL error:(NSError **)outError;
- (nullable RCMPayload *)renamePayload:(RCMPayload *)payload newName:(NSString *)newName error:(NSError **)outError;
- (void)deletePayload:(RCMPayload *)payload;

- (nullable NSString *)addCustomSource:(RCMCustomSource *)source;
- (void)removeCustomSourceNamed:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
