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
    GLubyte*    mYuv420p;
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
    mYuv420p = (GLubyte*)calloc(imageSize.width*imageSize.height*3/2, sizeof(GLubyte));
    mYuvCnt = 0;
    return self;
}
- (void)dealloc
{
    if( mYuvNv12 )
        free(mYuvNv12);
    if( mYuv420p )
        free(mYuv420p);
}

#pragma mark -
#pragma mark GPUImageInput protocol

- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex;
{
    // Convert
    TIMECHECKBEGIN(bgra);
    GLubyte* bgrabuf = [firstInputFramebuffer byteBuffer];
    int     bgra_stride = [firstInputFramebuffer bytesPerRow];
    ARGBToI420(bgrabuf, bgra_stride, mYuv420p, imageSize.width,
               mYuv420p+(int)(imageSize.width*imageSize.height), imageSize.width/2,
               mYuv420p+(int)(imageSize.width*imageSize.height*5/4), imageSize.width/2,
               imageSize.width, imageSize.height);
    I420ToNV12(mYuv420p, imageSize.width,
               mYuv420p+(int)(imageSize.width*imageSize.height), imageSize.width/2,
               mYuv420p+(int)(imageSize.width*imageSize.height*5/4), imageSize.width/2,
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
-(CVPixelBufferRef)rawBytesGpuForPixelBuffer;
{
    return [firstInputFramebuffer pixelBuffer];
}
-(CMSampleBufferRef)rawBytesGpuForSampleBuffer;
{
    CVPixelBufferRef pixel_buf = [firstInputFramebuffer pixelBuffer];
    OSStatus status;
    CMSampleBufferRef sampleBuffer;
    CMVideoFormatDescriptionRef cm_fmt_desc;
    
    status = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixel_buf, &cm_fmt_desc);
    CMSampleTimingInfo sample_time;
    sample_time.duration = kCMTimeInvalid;
    sample_time.presentationTimeStamp = CMTimeMake(mYuvCnt*50*1000000, 1000000000); // pts
    sample_time.presentationTimeStamp.flags = kCMTimeFlags_Valid;
    sample_time.decodeTimeStamp = kCMTimeInvalid;
    
    status = CMSampleBufferCreateForImageBuffer(NULL, pixel_buf, TRUE, NULL, NULL, cm_fmt_desc, &sample_time, &sampleBuffer);
    CFRelease(cm_fmt_desc);
    cm_fmt_desc=nil;
    return sampleBuffer;
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

-(GLubyte*)rawBytesForYuv420p;
{
    return mYuv420p;
}
-(GLubyte*)rawBytesForYuvNv12;
{
    return mYuvNv12;
}
- (CFDictionaryRef) videotoolbox_buffer_attributes_create:(int) width :(int) height :(OSType) pix_fmt;
{
    CFMutableDictionaryRef buffer_attributes;
    CFMutableDictionaryRef io_surface_properties;
    CFNumberRef cv_pix_fmt;
    CFNumberRef w;
    CFNumberRef h;
    
    w = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &width);
    h = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &height);
    cv_pix_fmt = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &pix_fmt);
    
    buffer_attributes = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                  4,
                                                  &kCFTypeDictionaryKeyCallBacks,
                                                  &kCFTypeDictionaryValueCallBacks);
    io_surface_properties = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                      0,
                                                      &kCFTypeDictionaryKeyCallBacks,
                                                      &kCFTypeDictionaryValueCallBacks);
    
    CFDictionarySetValue(buffer_attributes, kCVPixelBufferPixelFormatTypeKey, cv_pix_fmt);
    CFDictionarySetValue(buffer_attributes, kCVPixelBufferIOSurfacePropertiesKey, io_surface_properties);
    CFDictionarySetValue(buffer_attributes, kCVPixelBufferWidthKey, w);
    CFDictionarySetValue(buffer_attributes, kCVPixelBufferHeightKey, h);
    
    CFRelease(io_surface_properties);
    CFRelease(cv_pix_fmt);
    CFRelease(w);
    CFRelease(h);
    
    return buffer_attributes;
}
-(CVPixelBufferRef)rawBytesy420ForPixelBuffer;
{
    OSStatus status;
    CVPixelBufferRef pixel_buf;
    CFDictionaryRef attrs;
    attrs = [self videotoolbox_buffer_attributes_create:imageSize.width :imageSize.height :kCVPixelFormatType_420YpCbCr8Planar];
    void*  planedatas[3] = {mYuv420p, mYuv420p+(480*640), mYuv420p+(480*640*5/4)};
    size_t planewidths[3] = {imageSize.width,imageSize.width/2, imageSize.width/2};
    size_t planeheights[3] = {imageSize.height,imageSize.height/2, imageSize.height/2};
    size_t planestrides[3] = {imageSize.width,imageSize.width/2, imageSize.width/2}; // 试验 stride u v 的 stride是否要减半
    status = CVPixelBufferCreateWithPlanarBytes(NULL, imageSize.width, imageSize.height, kCVPixelFormatType_420YpCbCr8Planar,// 格式试验
                                                mYuv420p, (480*640*3/2), 3, planedatas, planewidths, planeheights, planestrides,
                                                nil, (__bridge void * _Nullable)(self), attrs, &pixel_buf);// 试验只传一种方式的数据 是连续的一块  或是 多块数据
//    status = CVPixelBufferCreateWithBytes(NULL, imageSize.width, imageSize.height, kCVPixelFormatType_420YpCbCr8Planar, mYuv420p, imageSize.width, NULL, (__bridge void * _Nullable)(self), attrs, &pixel_buf);
//    status = CVPixelBufferCreate(kCFAllocatorDefault, imageSize.width, imageSize.height, kCVPixelFormatType_420YpCbCr8Planar, attrs, &pixel_buf);
    CFRelease(attrs);
    status = CVPixelBufferLockBaseAddress(pixel_buf, 0);
    if (kCVReturnSuccess != status) {
        CVPixelBufferUnlockBaseAddress(pixel_buf, 0);
        pixel_buf=nil;
        return NULL;
    }
    void* baseAddr = CVPixelBufferGetBaseAddress(pixel_buf);
    size_t plane_width = CVPixelBufferGetWidthOfPlane(pixel_buf, 0);
    size_t plane_height = CVPixelBufferGetHeightOfPlane(pixel_buf, 0);
    //sanity check
    size_t y_bytePer_row = CVPixelBufferGetBytesPerRowOfPlane(pixel_buf, 0);
    size_t y_plane_height = CVPixelBufferGetHeightOfPlane(pixel_buf, 0);
    size_t y_plane_width = CVPixelBufferGetWidthOfPlane(pixel_buf, 0);
    
    size_t u_bytePer_row = CVPixelBufferGetBytesPerRowOfPlane(pixel_buf, 1);
    size_t u_plane_height = CVPixelBufferGetHeightOfPlane(pixel_buf, 1);
    size_t u_plane_width = CVPixelBufferGetWidthOfPlane(pixel_buf, 1);

    size_t v_bytePer_row = CVPixelBufferGetBytesPerRowOfPlane(pixel_buf, 2);
    size_t v_plane_height = CVPixelBufferGetHeightOfPlane(pixel_buf, 2);
    size_t v_plane_width = CVPixelBufferGetWidthOfPlane(pixel_buf, 2);

    uint8_t* y_src= (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixel_buf, 0);
//    memcpy(y_src, planedatas[0], planestrides[0]*planeheights[0]);
    uint8_t* u_src= (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixel_buf, 1);
//    memcpy(u_src, planedatas[1], planestrides[1]*planeheights[1]);
    uint8_t* v_src= (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixel_buf, 2);
//    memcpy(v_src, planedatas[2], planestrides[2]*planeheights[2]);
    int nlen = y_bytePer_row*y_plane_height + u_bytePer_row*u_plane_height + v_bytePer_row*v_plane_height;
    
    if( status != kCVReturnSuccess )
        NSLog(@"CVPixelBufferCreateWithPlanarBytes error:%ld", status);
    CVPixelBufferUnlockBaseAddress(pixel_buf, 0);
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
    // 去掉附加的属性试验
//    CVBufferSetAttachment(pixel_buf, km4, metadata, kCVAttachmentMode_ShouldPropagate);
//    CVBufferSetAttachment(pixel_buf, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVAttachmentMode_ShouldPropagate);
//    CVBufferSetAttachment(pixel_buf, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
//    CVBufferSetAttachment(pixel_buf, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    return pixel_buf;
}
-(CVPixelBufferRef)rawBytesnv12ForPixelBuffer;
{
    OSStatus status;
    CVPixelBufferRef pixel_buf;
    CFDictionaryRef empty; // empty value for attr value.
    CFMutableDictionaryRef attrs;
    empty = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); // our empty IOSurface properties dictionary
    attrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey, empty);
    void*  planedatas[3] = {mYuvNv12, mYuvNv12+(480*640), };// mYuv420p+(480*640*5/4)};
    size_t planewidths[3] = {imageSize.width,imageSize.width/2, };//240};
    size_t planeheights[3] = {imageSize.height,imageSize.height/2, };//320};
    size_t planestrides[3] = {imageSize.width,imageSize.width,};//240};
    status = CVPixelBufferCreateWithPlanarBytes(NULL, imageSize.width, imageSize.height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,// 格式试验
                                                mYuvNv12, 480*640*3/2, 2, planedatas, planewidths, planeheights, planestrides,
                                                nil, (__bridge void * _Nullable)(self), attrs, &pixel_buf);// 试验数据是一块  还是 多块 填充
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
    // 试验附加数据
    CVBufferSetAttachment(pixel_buf, km4, metadata, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel_buf, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel_buf, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel_buf, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    return pixel_buf;
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
    void*  planedatas[3] = {mYuvNv12, mYuvNv12+(480*640), };// mYuv420p+(480*640*5/4)};
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