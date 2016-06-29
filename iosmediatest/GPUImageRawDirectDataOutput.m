//
//  GPUImageRawDirectDataOutput.m
//  iosmediatest
//
//  Created by sks on 16/6/22.
//  Copyright © 2016年 sks. All rights reserved.
//
#import "GPUImageRawDirectDataOutput.h"
//
void ortp_get_cur_time(ortpTimeSpec *ret){
#if defined(_WIN32_WCE) || defined(WIN32)
    DWORD timemillis;
#	if defined(_WIN32_WCE)
    timemillis=GetTickCount();
#	else
    timemillis=timeGetTime();
#	endif
    ret->tv_sec=timemillis/1000;
    ret->tv_nsec=(timemillis%1000)*1000000LL;
#elif defined(__MACH__)
    struct timeb time_val;
    ftime (&time_val);
    ret->tv_sec = time_val.time;
    ret->tv_nsec = time_val.millitm * 1000000LL;
#elif defined(HAVE_POSIX_CLOCKS)
    struct timespec ts;
    ts.tv_sec = ts.tv_nsec = 0;
    if (clock_gettime(CLOCK_MONOTONIC,&ts)<0){
        ortp_fatal("clock_gettime() doesn't work: %s",strerror(errno));
    }
    ret->tv_sec=ts.tv_sec;
    ret->tv_nsec=ts.tv_nsec;
#else //defined(__MACH__) && defined(__GNUC__) && (__GNUC__ >= 3)
    struct timeval tv;
    gettimeofday(&tv, NULL);
    ret->tv_sec=tv.tv_sec;
    ret->tv_nsec=tv.tv_usec*1000LL;
#endif
}
uint64_t get_wallclock_ms(void){
    ortpTimeSpec ts;
    ortp_get_cur_time(&ts);
    return (ts.tv_sec*1000LL) + ((ts.tv_nsec+500000LL)/1000000LL);
}

#if defined(__arm__) && !defined(__aarch64__) && !defined(__ARM_NEON__)
#define LIBYUV_DISABLE_NEON
#endif
#include "libyuv/convert.h"
#include "libyuv.h"
@interface GPUImageRawDirectDataOutput()
{
    GPUImageFramebuffer *firstInputFramebuffer;
    
    GLubyte *_rawBytesForImage;
    CGSize imageSize;
    GLubyte*    mYuv420sp;
    GLubyte*    mYuvNv12;
    UInt64      mYuvCnt;
}

@end

@implementation GPUImageRawDirectDataOutput

@synthesize rawBytesForImage = _rawBytesForImage;
@synthesize newFrameAvailableBlock = _newFrameAvailableBlock;

#pragma mark -
#pragma mark Initialization and teardown
-(id)initWithImageSize:(CGSize)newImageSize;
{
    if (!(self = [super init]))
    {
        return nil;
    }
    imageSize = newImageSize;
    firstInputFramebuffer = nil;
    mYuvNv12 = (GLubyte*)calloc(imageSize.width*imageSize.height*3/2, sizeof(GLubyte));
    mYuv420sp = (GLubyte*)calloc(imageSize.width*imageSize.height*3/2, sizeof(GLubyte));
    mYuvCnt = 0;
    return self;
}
- (void)dealloc
{
    if( mYuvNv12 )
        free(mYuvNv12);
    if( mYuv420sp )
        free(mYuv420sp);
}

#pragma mark -
#pragma mark GPUImageInput protocol

- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex;
{
    // Convert
    TIMECHECKBEGIN(bgra);
    GLubyte* bgrabuf = [firstInputFramebuffer byteBuffer];
    int     bgra_stride = [firstInputFramebuffer bytesPerRow];
    ARGBToI420(bgrabuf, bgra_stride, mYuv420sp, imageSize.width,
               mYuv420sp+(int)(imageSize.width*imageSize.height), imageSize.width/2,
               mYuv420sp+(int)(imageSize.width*imageSize.height*5/4), imageSize.width/2,
               imageSize.width, imageSize.height);
    I420ToNV12(mYuv420sp, imageSize.width,
               mYuv420sp+(int)(imageSize.width*imageSize.height), imageSize.width/2,
               mYuv420sp+(int)(imageSize.width*imageSize.height*5/4), imageSize.width/2,
               mYuvNv12, imageSize.width,
               mYuvNv12+(int)(imageSize.width*imageSize.height), imageSize.width,
               imageSize.width, imageSize.height);
    TIMECHECKEND(bgra, 5, "bgra too long time ");
    mYuvCnt++;
    if (_newFrameAvailableBlock != NULL)
    {
        TIMECHECKBEGIN(newFrame);
        _newFrameAvailableBlock();
        TIMECHECKEND(newFrame, 10, "newFrame too long time");
    }
}

- (NSInteger)nextAvailableTextureIndex;
{
    return 0;
}

- (void)setInputFramebuffer:(GPUImageFramebuffer *)newInputFramebuffer atIndex:(NSInteger)textureIndex;
{
    if( firstInputFramebuffer )
        [firstInputFramebuffer unlock];
    firstInputFramebuffer = newInputFramebuffer;
    [firstInputFramebuffer lock];
}

- (void)setInputRotation:(GPUImageRotationMode)newInputRotation atIndex:(NSInteger)textureIndex;
{
}

- (void)setInputSize:(CGSize)newSize atIndex:(NSInteger)textureIndex;
{
    imageSize = newSize;
}
- (BOOL)enabled;
{
    return TRUE;
}
- (CGSize)maximumOutputSize;
{
    return imageSize;
}

- (void)endProcessing;
{
}

- (BOOL)shouldIgnoreUpdatesToThisTarget;
{
    return NO;
}

- (BOOL)wantsMonochromeInput;
{
    return NO;
}

- (void)setCurrentlyReceivingMonochromeInput:(BOOL)newValue;
{
}

#pragma mark -
#pragma mark Accessors

-(GLubyte*)rawBytesForYuv420sp;
{
    return mYuv420sp;
}
-(GLubyte*)rawBytesForYuvNv12;
{
    return mYuvNv12;
}

-(CMSampleBufferRef)rawBytesForSampleBuffer;
{
    OSStatus status;
    CMSampleBufferRef sampleBuffer;
    CVPixelBufferRef pixel_buf;
    CFDictionaryRef empty; // empty value for attr value.
    CFMutableDictionaryRef attrs;
    empty = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); // our empty IOSurface properties dictionary
    attrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey, empty);
    void*  planedatas[3] = {mYuvNv12, mYuvNv12+(480*640), };// mYuv420sp+(480*640*5/4)};
    size_t planewidths[3] = {imageSize.width,imageSize.width/2, };//240};
    size_t planeheights[3] = {imageSize.height,imageSize.height/2, };//320};
    size_t planestrides[3] = {imageSize.width,imageSize.width,};//240};
    status = CVPixelBufferCreateWithPlanarBytes(NULL, imageSize.width, imageSize.height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                                mYuvNv12, 480*640*3/2, 2, planedatas, planewidths, planeheights, planestrides,
                                                nil, (__bridge void * _Nullable)(self), attrs, &pixel_buf);
    CFMutableDictionaryRef metadata = CFDictionaryCreateMutable(nil, 3, nil, nil);
    CFStringRef km1 = CFStringCreateWithCString(nil, "SNR", kCFStringEncodingUTF8);
    Float64 vam1 = 14.25522169269836858518;
    CFNumberRef vm1 = CFNumberCreate(nil, kCFNumberFloat64Type, &vam1);
    CFDictionaryAddValue(metadata, km1, vm1);
    CFStringRef km2 = CFStringCreateWithCString(nil, "ExposureTime", kCFStringEncodingUTF8);
    Float64 vam2 = 0.00833300000000000013;
    CFNumberRef vm2 = CFNumberCreate(nil, kCFNumberFloat64Type, &vam2);
    CFDictionaryAddValue(metadata, km2, vm2);
    CFStringRef km3 = CFStringCreateWithCString(nil, "SensorID", kCFStringEncodingUTF8);
    SInt32 vam3 = 30518;
    CFNumberRef vm3 = CFNumberCreate(nil, kCFNumberSInt32Type, &vam3);
    CFDictionaryAddValue(metadata, km3, vm3);
    CFStringRef km4 = CFStringCreateWithCString(nil, "MetadataDictionary", kCFStringEncodingUTF8);
    CVBufferSetAttachment(pixel_buf, km4, metadata, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel_buf, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel_buf, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel_buf, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CMVideoFormatDescriptionRef cm_fmt_desc;
    CFMutableDictionaryRef extension = CFDictionaryCreateMutable(nil, 3, nil, nil);
    CFStringRef k1 = CFStringCreateWithCString(nil, "CVBytesPerRow", kCFStringEncodingUTF8);
    int va1 = 724;
    CFNumberRef v1 = CFNumberCreate(nil, kCFNumberSInt32Type, &va1);
    CFDictionaryAddValue(extension, k1, v1);
    CFStringRef k2 = CFStringCreateWithCString(nil, "Version", kCFStringEncodingUTF8);
    int va2 = 2;
    CFNumberRef v2 = CFNumberCreate(nil, kCFNumberSInt32Type, &va2);
    CFDictionaryAddValue(extension, k2, v2);
    CFStringRef k3 = CFStringCreateWithCString(nil, "CVImageBufferYCbCrMatrix", kCFStringEncodingUTF8);
    CFStringRef v3 = CFStringCreateWithCString(nil, "ITU_R_601_4", kCFStringEncodingUTF8);
    CFDictionaryAddValue(extension, k3, v3);

    //        status = CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, 480, 640, nil, &cm_fmt_desc);
    status = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixel_buf, &cm_fmt_desc);
//    CFMutableDictionaryRef extension = CMFormatDescriptionGetExtensions(cm_fmt_desc);
    //kCMFormatDescriptionExtensionKey_MetadataKeyTable
//    CFDictionaryAddValue(extension, kCMFormatDescriptionExtension_BytesPerRow, "724");
//    CFDictionaryAddValue(extension, kCMFormatDescriptionExtensionKey_MetadataKeyTable, metadata);
    //kCMFormatDescriptionExtension_BytesPerRow
    //CMFormatDescriptionGetExtension
    CMSampleTimingInfo sample_time;
    sample_time.duration = kCMTimeInvalid;
    sample_time.presentationTimeStamp = CMTimeMake(mYuvCnt*50*1000000, 1000000000); // pts
    sample_time.presentationTimeStamp.flags = kCMTimeFlags_Valid;
    sample_time.decodeTimeStamp = kCMTimeInvalid;
    
    status = CMSampleBufferCreateForImageBuffer(NULL, pixel_buf, TRUE, NULL, NULL, cm_fmt_desc, &sample_time, &sampleBuffer);
    //        CMSampleBufferGetSampleAttachmentsArray
    //        CVBufferSetAttachment   kCVImageBufferYCbCrMatrixKey
    //        CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo
    //        BOOL isencode = [mVideoEncode encodePixelBuffer:pixel_buf presentationTimeStamp:CMTimeMake(mH264Cnt*1000, 25) duration:CMTimeMake(1000, 25) forceKeyframe:forceKey];
    CFRelease(cm_fmt_desc);
    cm_fmt_desc=nil;
    CFRelease(pixel_buf);
    pixel_buf = nil;
    return sampleBuffer;
}

//- (GLubyte *)rawBytesForImage;
//{
//    _rawBytesForImage = [firstInputFramebuffer byteBuffer];
//    return _rawBytesForImage;
//}
//
//- (NSUInteger)bytesPerRowInOutput;
//{
//    return [firstInputFramebuffer bytesPerRow];
//}
@end