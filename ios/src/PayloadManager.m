#import "PayloadManager.h"
#import <zlib.h>

NSString *const PayloadManagerDidUpdateNotification = @"PayloadManagerDidUpdate";

static NSArray<NSDictionary *> *remoteSpecs(void) {
    return @[
        @{ @"name": @"fusee",         @"repo": @"Atmosphere-NX/Atmosphere",       @"asset": @"fusee.bin" },
        @{ @"name": @"hekate",        @"repo": @"CTCaer/hekate",                  @"asset": @"hekate_ctcaer", @"zip": @YES },
        @{ @"name": @"TegraExplorer", @"repo": @"suchmememanyskill/TegraExplorer", @"asset": @"TegraExplorer.bin" },
    ];
}

@implementation RCMPayload

- (instancetype)initWithName:(NSString *)name fileURL:(NSURL *)url isCustom:(BOOL)custom version:(NSString *)version {
    self = [super init];
    self.name = name;
    self.fileURL = url;
    self.isCustom = custom;
    self.version = version;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
    self.fileSize = [attrs[NSFileSize] longLongValue];
    return self;
}

@end

@implementation RCMCustomSource
@end

static NSString *const kCustomSourcesDefaultsKey = @"custom_sources";

@interface PayloadManager ()
@property (nonatomic, strong) NSMutableArray<RCMPayload *> *mutablePayloads;
@property (nonatomic, strong) NSMutableArray<RCMCustomSource *> *mutableCustomSources;
@end

@implementation PayloadManager

+ (instancetype)shared {
    static PayloadManager *instance;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ instance = [PayloadManager new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    _mutablePayloads = [NSMutableArray new];
    [self loadCustomSources];
    [self refresh];
    return self;
}

- (NSArray<RCMPayload *> *)payloads { return [_mutablePayloads copy]; }
- (NSArray<RCMCustomSource *> *)customSources { return [_mutableCustomSources copy]; }

- (void)loadCustomSources {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kCustomSourcesDefaultsKey];
    NSMutableArray *result = [NSMutableArray new];
    for (NSDictionary *d in raw) {
        RCMCustomSource *s = [RCMCustomSource new];
        s.name = d[@"name"] ?: @"";
        s.repo = d[@"repo"] ?: @"";
        s.assetMatch = d[@"assetMatch"] ?: @"";
        s.isZip = [d[@"isZip"] boolValue];
        s.zipInnerPattern = d[@"zipInnerPattern"] ?: @"*.bin";
        [result addObject:s];
    }
    _mutableCustomSources = result;
}

- (void)saveCustomSources {
    NSMutableArray *raw = [NSMutableArray new];
    for (RCMCustomSource *s in _mutableCustomSources) {
        [raw addObject:@{
            @"name": s.name,
            @"repo": s.repo,
            @"assetMatch": s.assetMatch,
            @"isZip": @(s.isZip),
            @"zipInnerPattern": s.zipInnerPattern,
        }];
    }
    [[NSUserDefaults standardUserDefaults] setObject:raw forKey:kCustomSourcesDefaultsKey];
}

- (NSString *)sanitizeSourceKey:(NSString *)name {
    NSCharacterSet *alnum = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString *key = [NSMutableString new];
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        if ([alnum characterIsMember:c]) [key appendFormat:@"%C", c];
    }
    NSString *lower = key.lowercaseString;
    return lower.length > 0 ? lower : [[[NSUUID UUID] UUIDString] substringToIndex:8];
}

- (nullable NSString *)addCustomSource:(RCMCustomSource *)source {
    NSString *name = [source.name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *repo = [source.repo stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *assetMatch = [source.assetMatch stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (name.length == 0 || repo.length == 0 || assetMatch.length == 0) return @"All fields are required.";
    if ([repo rangeOfString:@"/"].location == NSNotFound) return @"Repository must be in the form owner/repo.";

    NSArray<NSString *> *reserved = @[@"fusee", @"hekate", @"tegraexplorer", @"custom"];
    if ([reserved containsObject:name.lowercaseString]) return @"That name is reserved, please choose another.";

    for (RCMCustomSource *existing in _mutableCustomSources) {
        if ([existing.name caseInsensitiveCompare:name] == NSOrderedSame)
            return @"A source with that name already exists.";
    }

    RCMCustomSource *clean = [RCMCustomSource new];
    clean.name = name;
    clean.repo = repo;
    clean.assetMatch = assetMatch;
    clean.isZip = source.isZip;
    NSString *pattern = [source.zipInnerPattern stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    clean.zipInnerPattern = pattern.length > 0 ? pattern : @"*.bin";

    [_mutableCustomSources addObject:clean];
    [self saveCustomSources];
    [self refresh];
    return nil;
}

- (void)removeCustomSourceNamed:(NSString *)name {
    RCMCustomSource *target = nil;
    for (RCMCustomSource *s in _mutableCustomSources) {
        if ([s.name isEqualToString:name]) { target = s; break; }
    }

    NSMutableArray *filtered = [NSMutableArray new];
    for (RCMCustomSource *s in _mutableCustomSources) {
        if (![s.name isEqualToString:name]) [filtered addObject:s];
    }
    _mutableCustomSources = filtered;
    [self saveCustomSources];

    if (target) {
        NSString *cacheKey = [@"custom_" stringByAppendingString:[self sanitizeSourceKey:target.name]];
        NSURL *cacheDir = [self cacheDir];
        NSArray *files = [[NSFileManager defaultManager]
            contentsOfDirectoryAtURL:cacheDir includingPropertiesForKeys:nil options:0 error:nil];
        for (NSURL *f in files) {
            NSString *fname = f.lastPathComponent;
            BOOL matches = [fname isEqualToString:[cacheKey stringByAppendingString:@".version"]]
                || [fname isEqualToString:[cacheKey stringByAppendingString:@".localpath"]]
                || [fname hasPrefix:[cacheKey stringByAppendingString:@"__"]]
                || [fname isEqualToString:[NSString stringWithFormat:@"__%@_tmp__", cacheKey]];
            if (matches) [[NSFileManager defaultManager] removeItemAtURL:f error:nil];
        }
    }

    [self refresh];
}

- (NSArray<NSDictionary *> *)allSpecs {
    NSMutableArray *specs = [remoteSpecs() mutableCopy];
    for (RCMCustomSource *src in _mutableCustomSources) {
        NSString *cacheKey = [@"custom_" stringByAppendingString:[self sanitizeSourceKey:src.name]];
        NSMutableDictionary *spec = [NSMutableDictionary dictionaryWithDictionary:@{
            @"name": src.name,
            @"repo": src.repo,
            @"asset": src.assetMatch,
            @"cacheKey": cacheKey,
            @"custom": @YES,
        }];
        if (src.isZip) {
            spec[@"zip"] = @YES;
            spec[@"innerPattern"] = src.zipInnerPattern.length > 0 ? src.zipInnerPattern : @"*.bin";
        }
        [specs addObject:spec];
    }
    return specs;
}

- (BOOL)fileName:(NSString *)fileName matchesPattern:(NSString *)pattern {
    if ([pattern rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*?"]].location != NSNotFound) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF LIKE[c] %@", pattern];
        return [predicate evaluateWithObject:fileName];
    }
    return [fileName rangeOfString:pattern options:NSCaseInsensitiveSearch].location != NSNotFound;
}

- (NSURL *)cacheDir {
    NSURL *docs = [[[NSFileManager defaultManager]
        URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *dir = [docs URLByAppendingPathComponent:@"payloads"];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir
                             withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (NSURL *)customDir {
    NSURL *docs = [[[NSFileManager defaultManager]
        URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *dir = [docs URLByAppendingPathComponent:@"custom"];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir
                             withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (nullable NSData *)intermezzoData {

    NSURL *url = [[NSBundle mainBundle] URLForResource:@"intermezzo" withExtension:@"bin"];
    return url ? [NSData dataWithContentsOfURL:url] : nil;
}

- (void)refresh {
    [_mutablePayloads removeAllObjects];

    for (NSDictionary *spec in [self allSpecs]) {
        NSString *name = spec[@"name"];
        NSString *cacheKey = spec[@"cacheKey"] ?: name;
        NSURL *versionFile = [[self cacheDir] URLByAppendingPathComponent:[cacheKey stringByAppendingString:@".version"]];
        NSString *version = [NSString stringWithContentsOfURL:versionFile encoding:NSUTF8StringEncoding error:nil];
        NSURL *file = [self resolveLocalFile:spec];
        if (file) {
            RCMPayload *p = [[RCMPayload alloc] initWithName:name fileURL:file isCustom:NO version:version];
            [_mutablePayloads addObject:p];
        }
    }

    NSArray *contents = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:[self customDir]
      includingPropertiesForKeys:nil options:0 error:nil];
    for (NSURL *url in contents) {
        if ([url.pathExtension.lowercaseString isEqualToString:@"bin"]) {
            NSString *name = url.lastPathComponent.stringByDeletingPathExtension;
            RCMPayload *p = [[RCMPayload alloc] initWithName:name fileURL:url isCustom:YES version:nil];
            [_mutablePayloads addObject:p];
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:PayloadManagerDidUpdateNotification object:self];
    });
}

- (nullable NSURL *)resolveLocalFile:(NSDictionary *)spec {
    NSString *name = spec[@"name"];
    NSURL *cacheDir = [self cacheDir];
    if ([spec[@"custom"] boolValue]) {
        NSString *cacheKey = spec[@"cacheKey"];
        NSURL *marker = [cacheDir URLByAppendingPathComponent:[cacheKey stringByAppendingString:@".localpath"]];
        NSString *path = [NSString stringWithContentsOfURL:marker encoding:NSUTF8StringEncoding error:nil];
        if (!path) return nil;
        path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [[NSFileManager defaultManager] fileExistsAtPath:path] ? [NSURL fileURLWithPath:path] : nil;
    }
    if ([name isEqualToString:@"hekate"]) {
        NSArray *files = [[NSFileManager defaultManager]
            contentsOfDirectoryAtURL:cacheDir includingPropertiesForKeys:nil options:0 error:nil];
        for (NSURL *f in files) {
            if ([f.lastPathComponent hasPrefix:@"hekate_ctcaer"] &&
                [f.pathExtension isEqualToString:@"bin"]) return f;
        }
        return nil;
    }
    NSURL *f = [cacheDir URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.bin", name]];
    return [[NSFileManager defaultManager] fileExistsAtPath:f.path] ? f : nil;
}

- (void)fetchAllWithLog:(void (^)(NSString *))logBlock completion:(void (^)(void))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (NSDictionary *spec in [self allSpecs]) {
            NSString *name = spec[@"name"];
            logBlock([NSString stringWithFormat:@"Checking %@...", name]);
            NSError *e = nil;
            [self fetchSpec:spec logBlock:logBlock error:&e];
            if (e) logBlock([NSString stringWithFormat:@"  [WARN] %@: %@", name, e.localizedDescription]);
        }
        [self refresh];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(); });
    });
}

- (BOOL)fetchSpec:(NSDictionary *)spec logBlock:(void(^)(NSString *))log error:(NSError **)outError {
    NSString *name = spec[@"name"];
    NSString *repo = spec[@"repo"];
    NSString *cacheKey = spec[@"cacheKey"] ?: name;
    BOOL isZip = [spec[@"zip"] boolValue];
    BOOL isCustom = [spec[@"custom"] boolValue];

    NSString *apiURL = [NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", repo];
    NSData *data = [self httpGET:apiURL error:outError];
    if (!data) return NO;

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:outError];
    if (!json) return NO;

    NSString *tag = json[@"tag_name"];
    NSString *version = [tag stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@"vV"]];

    NSURL *versionFile = [[self cacheDir] URLByAppendingPathComponent:[cacheKey stringByAppendingString:@".version"]];
    NSString *cached = [NSString stringWithContentsOfURL:versionFile encoding:NSUTF8StringEncoding error:nil];
    if ([cached isEqualToString:version] && [self resolveLocalFile:spec]) {
        log([NSString stringWithFormat:@"  %@ already up to date (%@).", name, tag]);
        return YES;
    }

    NSString *assetPattern = spec[@"asset"];
    NSString *dlURL = nil, *assetName = nil;
    for (NSDictionary *asset in json[@"assets"]) {
        NSString *n = asset[@"name"];
        BOOL matches = isCustom
            ? [self fileName:n matchesPattern:assetPattern]
            : ([n hasPrefix:assetPattern] && (!isZip || [n hasSuffix:@".zip"]));
        if (matches) {
            dlURL = asset[@"browser_download_url"];
            assetName = n;
            break;
        }
    }
    if (!dlURL) { log([NSString stringWithFormat:@"  [WARN] No matching asset for %@.", name]); return YES; }

    log([NSString stringWithFormat:@"  Downloading %@ %@...", name, tag]);
    NSURL *tmpURL = [[self cacheDir] URLByAppendingPathComponent:
        isCustom ? [NSString stringWithFormat:@"%@__%@", cacheKey, assetName] : assetName];
    if (![self download:dlURL toURL:tmpURL logBlock:log error:outError]) return NO;

    NSURL *finalURL = tmpURL;
    if (isZip) {
        log([NSString stringWithFormat:@"  Extracting %@...", name]);
        NSURL *extracted = isCustom
            ? [self extractCustomZipAtURL:tmpURL cacheKey:cacheKey innerPattern:spec[@"innerPattern"] error:outError]
            : [self extractHekateZip:tmpURL error:outError];
        [[NSFileManager defaultManager] removeItemAtURL:tmpURL error:nil];
        if (!extracted) return NO;
        finalURL = extracted;
    }

    if (isCustom) {
        NSURL *marker = [[self cacheDir] URLByAppendingPathComponent:[cacheKey stringByAppendingString:@".localpath"]];
        [finalURL.path writeToURL:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }

    [version writeToURL:versionFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    log([NSString stringWithFormat:@"  %@ %@ ready.", name, tag]);
    return YES;
}

- (nullable NSURL *)extractHekateZip:(NSURL *)zipURL error:(NSError **)outError {

    NSURL *tmpDir = [[self cacheDir] URLByAppendingPathComponent:@"__hekate_tmp__"];
    [[NSFileManager defaultManager] createDirectoryAtURL:tmpDir
                             withIntermediateDirectories:YES attributes:nil error:nil];

    NSData *zipData = [NSData dataWithContentsOfURL:zipURL];
    if (!zipData) {
        if (outError) *outError = [NSError errorWithDomain:@"OmniRCM" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Could not read zip file"}];
        return nil;
    }

    NSURL *result = [self extractBinFromZipData:zipData toDir:tmpDir error:outError];

    if (result) {
        NSURL *dest = [[self cacheDir] URLByAppendingPathComponent:result.lastPathComponent];
        [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:result toURL:dest error:nil];
        [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
        return dest;
    }
    return nil;
}

- (nullable NSURL *)extractBinFromZipData:(NSData *)data toDir:(NSURL *)dir error:(NSError **)outError {

    const uint8_t *bytes = data.bytes;
    NSUInteger len = data.length;
    NSUInteger offset = 0;
    NSURL *found = nil;

    while (offset + 30 < len) {
        uint32_t sig = OSReadLittleInt32(bytes, offset);
        if (sig != 0x04034b50) { offset++; continue; }

        uint16_t compression = OSReadLittleInt16(bytes, offset + 8);
        uint32_t compSize    = OSReadLittleInt32(bytes, offset + 18);
        uint32_t uncompSize  = OSReadLittleInt32(bytes, offset + 22);
        uint16_t nameLen     = OSReadLittleInt16(bytes, offset + 26);
        uint16_t extraLen    = OSReadLittleInt16(bytes, offset + 28);

        NSString *name = [[NSString alloc] initWithBytes:bytes + offset + 30
                                                   length:nameLen encoding:NSUTF8StringEncoding];
        NSUInteger dataOffset = offset + 30 + nameLen + extraLen;

        if ([name hasSuffix:@".bin"] && [name hasPrefix:@"hekate_ctcaer"]) {
            NSData *fileData = nil;

            if (compression == 0) {

                if (dataOffset + uncompSize <= len)
                    fileData = [NSData dataWithBytes:bytes + dataOffset length:uncompSize];
            } else if (compression == 8) {

                if (dataOffset + compSize <= len) {
                    NSMutableData *out = [NSMutableData dataWithLength:uncompSize];
                    z_stream stream = {0};
                    stream.next_in   = (Bytef *)(bytes + dataOffset);
                    stream.avail_in  = compSize;
                    stream.next_out  = out.mutableBytes;
                    stream.avail_out = uncompSize;
                    if (inflateInit2(&stream, -15) == Z_OK) {
                        int zr = inflate(&stream, Z_FINISH);
                        inflateEnd(&stream);
                        if (zr == Z_STREAM_END)
                            fileData = out;
                    }
                }
            }

            if (fileData) {
                NSString *baseName = [[name componentsSeparatedByString:@"/"] lastObject];
                NSURL *dest = [dir URLByAppendingPathComponent:baseName];
                [fileData writeToURL:dest atomically:YES];
                found = dest;
            }
        }

        offset = dataOffset + compSize;
    }

    if (!found && outError) {
        *outError = [NSError errorWithDomain:@"OmniRCM" code:2
            userInfo:@{NSLocalizedDescriptionKey: @"hekate_ctcaer*.bin not found in zip"}];
    }
    return found;
}

- (nullable NSURL *)extractCustomZipAtURL:(NSURL *)zipURL cacheKey:(NSString *)cacheKey innerPattern:(NSString *)innerPattern error:(NSError **)outError {

    NSURL *tmpDir = [[self cacheDir] URLByAppendingPathComponent:[NSString stringWithFormat:@"__%@_tmp__", cacheKey]];
    [[NSFileManager defaultManager] createDirectoryAtURL:tmpDir
                             withIntermediateDirectories:YES attributes:nil error:nil];

    NSData *zipData = [NSData dataWithContentsOfURL:zipURL];
    if (!zipData) {
        if (outError) *outError = [NSError errorWithDomain:@"OmniRCM" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"Could not read zip file"}];
        return nil;
    }

    NSString *pattern = innerPattern.length > 0 ? innerPattern : @"*.bin";
    NSURL *result = [self extractFileFromZipData:zipData matchingPattern:pattern toDir:tmpDir error:outError];

    if (result) {
        NSURL *dest = [[self cacheDir] URLByAppendingPathComponent:
            [NSString stringWithFormat:@"%@__%@", cacheKey, result.lastPathComponent]];
        [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:result toURL:dest error:nil];
        [[NSFileManager defaultManager] removeItemAtURL:tmpDir error:nil];
        return dest;
    }
    return nil;
}

- (nullable NSURL *)extractFileFromZipData:(NSData *)data matchingPattern:(NSString *)pattern toDir:(NSURL *)dir error:(NSError **)outError {

    const uint8_t *bytes = data.bytes;
    NSUInteger len = data.length;
    NSUInteger offset = 0;
    NSURL *found = nil;

    while (offset + 30 < len) {
        uint32_t sig = OSReadLittleInt32(bytes, offset);
        if (sig != 0x04034b50) { offset++; continue; }

        uint16_t compression = OSReadLittleInt16(bytes, offset + 8);
        uint32_t compSize    = OSReadLittleInt32(bytes, offset + 18);
        uint32_t uncompSize  = OSReadLittleInt32(bytes, offset + 22);
        uint16_t nameLen     = OSReadLittleInt16(bytes, offset + 26);
        uint16_t extraLen    = OSReadLittleInt16(bytes, offset + 28);

        NSString *name = [[NSString alloc] initWithBytes:bytes + offset + 30
                                                   length:nameLen encoding:NSUTF8StringEncoding];
        NSUInteger dataOffset = offset + 30 + nameLen + extraLen;
        NSString *baseName = [[name componentsSeparatedByString:@"/"] lastObject];

        if ([self fileName:baseName matchesPattern:pattern]) {
            NSData *fileData = nil;

            if (compression == 0) {

                if (dataOffset + uncompSize <= len)
                    fileData = [NSData dataWithBytes:bytes + dataOffset length:uncompSize];
            } else if (compression == 8) {

                if (dataOffset + compSize <= len) {
                    NSMutableData *out = [NSMutableData dataWithLength:uncompSize];
                    z_stream stream = {0};
                    stream.next_in   = (Bytef *)(bytes + dataOffset);
                    stream.avail_in  = compSize;
                    stream.next_out  = out.mutableBytes;
                    stream.avail_out = uncompSize;
                    if (inflateInit2(&stream, -15) == Z_OK) {
                        int zr = inflate(&stream, Z_FINISH);
                        inflateEnd(&stream);
                        if (zr == Z_STREAM_END)
                            fileData = out;
                    }
                }
            }

            if (fileData) {
                NSURL *dest = [dir URLByAppendingPathComponent:baseName];
                [fileData writeToURL:dest atomically:YES];
                found = dest;
            }
        }

        offset = dataOffset + compSize;
    }

    if (!found && outError) {
        *outError = [NSError errorWithDomain:@"OmniRCM" code:2
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No file matching \"%@\" found in zip", pattern]}];
    }
    return found;
}

- (nullable NSData *)httpGET:(NSString *)urlString error:(NSError **)outError {
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                    timeoutInterval:30];
    NSURLResponse *resp = nil;
    return [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:outError];
}

- (BOOL)download:(NSString *)urlString toURL:(NSURL *)dest
        logBlock:(void(^)(NSString *))log error:(NSError **)outError {
    NSData *data = [self httpGET:urlString error:outError];
    if (!data) return NO;
    return [data writeToURL:dest options:NSDataWritingAtomic error:outError];
}

- (NSString *)sanitizeBaseName:(NSString *)raw {
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSArray *parts = [trimmed componentsSeparatedByCharactersInSet:invalid];
    NSString *cleaned = [parts componentsJoinedByString:@"_"];
    cleaned = [cleaned stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@". "]];
    return cleaned.length > 0 ? cleaned : @"payload";
}

- (NSString *)baseNameFromDisplayName:(NSString *)displayName {
    NSString *lastComponent = displayName.lastPathComponent;
    NSString *withoutExt = lastComponent.stringByDeletingPathExtension;
    if (withoutExt.length == 0) withoutExt = lastComponent;
    return [self sanitizeBaseName:withoutExt];
}

- (NSURL *)uniqueCustomFileForBaseName:(NSString *)baseName {
    NSURL *dir = [self customDir];
    NSURL *candidate = [dir URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"bin"]];
    NSInteger counter = 1;
    while ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) {
        NSString *name = [NSString stringWithFormat:@"%@ (%ld)", baseName, (long)counter];
        candidate = [dir URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"bin"]];
        counter++;
    }
    return candidate;
}

- (nullable RCMPayload *)addCustomPayloadFromURL:(NSURL *)sourceURL error:(NSError **)outError {
    NSString *base = [self baseNameFromDisplayName:sourceURL.lastPathComponent];
    NSURL *dest = [self uniqueCustomFileForBaseName:base];
    if (![[NSFileManager defaultManager] copyItemAtURL:sourceURL toURL:dest error:outError])
        return nil;
    [self refresh];
    return [[RCMPayload alloc] initWithName:dest.lastPathComponent.stringByDeletingPathExtension
                                    fileURL:dest isCustom:YES version:nil];
}

- (nullable RCMPayload *)renamePayload:(RCMPayload *)payload newName:(NSString *)newName error:(NSError **)outError {
    if (!payload.isCustom) return nil;

    NSString *newBase = [self baseNameFromDisplayName:newName];
    NSString *currentBase = payload.fileURL.lastPathComponent.stringByDeletingPathExtension;
    if ([newBase isEqualToString:currentBase]) return payload;

    NSURL *dest = [self uniqueCustomFileForBaseName:newBase];
    if (![[NSFileManager defaultManager] moveItemAtURL:payload.fileURL toURL:dest error:outError])
        return nil;

    [self refresh];
    for (RCMPayload *p in self.mutablePayloads) {
        if ([p.fileURL.path isEqualToString:dest.path]) return p;
    }
    return [[RCMPayload alloc] initWithName:dest.lastPathComponent.stringByDeletingPathExtension
                                    fileURL:dest isCustom:YES version:nil];
}

- (void)deletePayload:(RCMPayload *)payload {
    if (!payload.isCustom) return;
    [[NSFileManager defaultManager] removeItemAtURL:payload.fileURL error:nil];
    [self refresh];
}

@end
