//
//  ViewController.m
//  iosmediatest
//
//  Created by sks on 16/4/21.
//  Copyright © 2016年 sks. All rights reserved.
//

#import "ViewController.h"
//@import AVFoundation;
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "VideoToolboxPlus.h"
#include <pthread.h>
#include "GPUImageVideoConversion.h"
#include "GPUImageRawDirectDataOutput.h"
#include "GPUImage.h"
//#ifdef __cpulspuls
#if defined(__arm__) && !defined(__aarch64__) && !defined(__ARM_NEON__)
#define LIBYUV_DISABLE_NEON
#endif
//extern "C" {
#include "libyuv/convert.h"
#include "libyuv.h"
//};
//#endif
@interface ViewController () <AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, VTPCompressionSessionDelegate>{
    VTPCompressionSession*  mVideoEncode;
    FILE*       fdyuv;
    FILE*       fdgpu;
    UInt64      mH264Cnt;
    UInt64      mH264EncCnt;
    UInt64      mEstimateBitrate;
    GPUImageVideoConversion*    mConversion;
    GPUImageSoftenFilter* mfilter;
    GPUImageView* mGpuview;
    GPUImageRawDirectDataOutput*  mRawOutput;
    dispatch_queue_t        mbeautyq;
    dispatch_queue_t        mencoderq;
    char*                   mYuv420p;
}
@property (strong, nonatomic) AVCaptureSession *capsession;
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *cap_preview_layer;
@property (strong, nonatomic) AVCaptureMovieFileOutput *fileout;
@property (strong, nonatomic) AVCaptureStillImageOutput *imageout;
@property (strong, nonatomic) AVCaptureVideoDataOutput *vdataout;
@property (strong, nonatomic) AVCaptureAudioDataOutput *adataout;
@property (strong, nonatomic) AVCaptureDeviceInput *capdevinput;
@property (strong, nonatomic) AVCaptureDeviceInput *capdevaudioinput;
@property (strong, nonatomic) dispatch_queue_t videoqueue;
@property (weak, nonatomic) IBOutlet UIButton *button1;
@property (weak, nonatomic) IBOutlet UIButton *capturebtn;
@property (weak, nonatomic) IBOutlet UIView *preview_cap;
@property (weak, nonatomic) IBOutlet UIButton *switchbtn;
@property (weak, nonatomic) IBOutlet UIButton *takephoto;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    mbeautyq = dispatch_queue_create("live.sdk.beauty.video", NULL);
    mencoderq = dispatch_queue_create("live.sdk.bgratoi420.video", NULL);
    mH264Cnt = 0;
    mH264EncCnt = 0;
    mEstimateBitrate = 0;
    mYuv420p = (char*)calloc(480*640*3/2, sizeof(char));
    mConversion = [[GPUImageVideoConversion alloc] initWithSessionPreset:AVCaptureSessionPreset640x480 cameraPosition:AVCaptureDevicePositionBack];
    mfilter = [[GPUImageSoftenFilter alloc] init];
    [mfilter setSoftenLevel:0.75];
    mGpuview = [[GPUImageView alloc] initWithFrame:CGRectMake(0, 0, 320, 360)];
//    mRawOutput = [[GPUImageRawDataOutput alloc] initWithImageSize:CGSizeMake(480, 640) resultsInBGRAFormat:NO];
    mRawOutput = [[GPUImageRawDirectDataOutput alloc] initWithImageSize:CGSizeMake(480, 640)];
    
    __unsafe_unretained GPUImageRawDirectDataOutput * weakOutput = mRawOutput;
    [mRawOutput setNewFrameAvailableBlock:^{
        //GLubyte* buf=[weakOutput rawBytesForImage];
        CMSampleBufferRef sampleBuffer = [weakOutput rawBytesForSampleBuffer];
//        GLubyte* buf = [weakOutput rawBytesForYuvNv21];
        
        CMTime timestamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
        CVImageBufferRef frame = CMSampleBufferGetImageBuffer(sampleBuffer);
        size_t nlen = CMBlockBufferGetDataLength(CMSampleBufferGetDataBuffer(sampleBuffer));
        CVReturn status = CVPixelBufferLockBaseAddress(frame, kCVPixelBufferLock_ReadOnly);
        if (kCVReturnSuccess != status) {
            CVPixelBufferUnlockBaseAddress(frame, 0);
            frame=nil;
            return;
        }
        /*kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange*/
        size_t plane_width = CVPixelBufferGetWidthOfPlane(frame, 0);
        size_t plane_height = CVPixelBufferGetHeightOfPlane(frame, 0);
        //sanity check
        size_t y_bytePer_row = CVPixelBufferGetBytesPerRowOfPlane(frame, 0);
        size_t y_plane_height = CVPixelBufferGetHeightOfPlane(frame, 0);
        size_t y_plane_width = CVPixelBufferGetWidthOfPlane(frame, 0);
        
        size_t cbcr_plane_height = CVPixelBufferGetHeightOfPlane(frame, 1);
        size_t cbcr_plane_width = CVPixelBufferGetWidthOfPlane(frame, 1);
        size_t cbcr_bytePer_row = CVPixelBufferGetBytesPerRowOfPlane(frame, 1);
        
        uint8_t* y_src= (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(frame, 0);
        uint8_t* cbcr_src= (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(frame, 1);
        nlen = y_bytePer_row*y_plane_height + cbcr_bytePer_row*cbcr_plane_height;
        
//        fwrite(y_src, y_bytePer_row*y_plane_height, 1, fdgpu);
//        fwrite(cbcr_src, cbcr_bytePer_row*cbcr_plane_height, 1, fdgpu);
        
        BOOL forceKey = FALSE;
        if( mH264Cnt%25 == 0 )
            forceKey = TRUE;
        BOOL isencode = [mVideoEncode encodeSampleBuffer:sampleBuffer forceKeyframe:forceKey];
        mH264Cnt++;
        NSLog(@"AVCapture VideoData Output....time:%lld w:%lu h:%lu isenc:%d cnt:%llu len:%lu", timestamp.value, plane_width, plane_height, 1, mH264Cnt, nlen);
        CVPixelBufferUnlockBaseAddress(frame, 0);
    }];
/*    [mRawOutput setNewFrameAvailableBlock:^{
        dispatch_async(mencoderq, ^{
            TIMECHECKBEGIN(bgra);
            [weakOutput lockFramebufferForReading];
            GLubyte *outputBytes = [weakOutput rawBytesForImage];
            NSInteger bytesPerRow = [weakOutput bytesPerRowInOutput];
            TIMECHECKEND(bgra, 5, "rawBytesForImage great time");
            TIMECHECKBEGIN(libyuv);
            ARGBToI420(outputBytes, bytesPerRow, mYuv420p, 480, mYuv420p+(480*640), 240, mYuv420p+(480*640*5/4), 240, 480, 640);
            TIMECHECKEND(libyuv, 5, "ARGBToI420 loog time");
            [weakOutput unlockFramebufferAfterReading];
            mH264EncCnt++;
            NSLog(@"out queue %llu", mH264EncCnt);
        });
        mH264Cnt++;
        NSLog(@"in queue %llu", mH264Cnt);
*/        //NSLog(@"Bytes per row: %ld", (unsigned long)bytesPerRow);
//        memcpy(mYuv420p, outputBytes, (480*640*3/2));
//        ARGBToNV12(outputBytes, bytesPerRow, mYuv420p, 480, mYuv420p+(480*640), 480, 480, 640);
//        NV12ToI420(outputBytes, 480, outputBytes+(480*640), 480, mYuv420p, 480, mYuv420p+(480*640), 240, mYuv420p+(480*640)+(240*320), 240, 480, 640);
        
//        mH264Cnt++;
//        BOOL forceKey = FALSE;
//        if( mH264Cnt%25 == 0 )
//            forceKey = TRUE;
        
        OSStatus status;
        CMSampleBufferRef sampleBuffer;
#if 1
/*        CVPixelBufferRef pixel_buf;
        void*  planedatas[3] = {mYuv420p, mYuv420p+(480*640), };// mYuv420p+(480*640*5/4)};
        size_t planewidths[3] = {480,240, };//240};
        size_t planeheights[3] = {640,320, };//320};
        size_t planestrides[3] = {480,480,};//240};
        status = CVPixelBufferCreateWithPlanarBytes(NULL, 480, 640, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, mYuv420p, 480*640*3/2, 2, planedatas, planewidths, planeheights, planestrides, nil, (__bridge void * _Nullable)(self), nil, &pixel_buf);
        CMVideoFormatDescriptionRef cm_fmt_desc;
//        status = CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, 480, 640, nil, &cm_fmt_desc);
        status = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixel_buf, &cm_fmt_desc);
        CMSampleTimingInfo sample_time;
        sample_time.duration = CMTimeMake(1000, 25);
        sample_time.presentationTimeStamp = CMTimeMake(mH264Cnt*1000, 25); // pts
        sample_time.decodeTimeStamp = kCMTimeInvalid;
        status = CMSampleBufferCreateForImageBuffer(NULL, pixel_buf, TRUE, NULL, NULL, cm_fmt_desc, &sample_time, &sampleBuffer);
//        CMSampleBufferGetSampleAttachmentsArray
//        CVBufferSetAttachment   kCVImageBufferYCbCrMatrixKey
//        CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == kCFCompareEqualTo
//        BOOL isencode = [mVideoEncode encodePixelBuffer:pixel_buf presentationTimeStamp:CMTimeMake(mH264Cnt*1000, 25) duration:CMTimeMake(1000, 25) forceKeyframe:forceKey];
        CFRelease(pixel_buf);
        pixel_buf = NULL;*/
#else
        CMBlockBufferRef block_buf;
        CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, mYuv420p, 480*640*3/2, kCFAllocatorNull, NULL, 0, 480*640*3/2, 0, &block_buf);
        CMFormatDescriptionRef cm_fmt_desc;
        CFMutableDictionaryRef config_info = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                                       1,
                                                                       &kCFTypeDictionaryKeyCallBacks,
                                                                       &kCFTypeDictionaryValueCallBacks);
//        CFDictionarySetValue(config_info, kCMFormatDescription, <#const void *value#>)
//        kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms
        status = CMFormatDescriptionCreate ( kCFAllocatorDefault, // Allocator
                                            kCMMediaType_Video,
                                            'I420',
                                            config_info,
                                            &cm_fmt_desc );
        CMSampleTimingInfo sampleTimingInfo = {CMTimeMake(1, 300)};
        status = CMSampleBufferCreate(kCFAllocatorDefault, block_buf, TRUE, 0, 0, cm_fmt_desc, 1, 0, &sampleTimingInfo, 0, NULL, &sampleBuffer);
        CFRelease(block_buf);
        block_buf = NULL;
#endif
        //BOOL isencode = 0;//[mVideoEncode encodeSampleBuffer:sampleBuffer forceKeyframe:forceKey];
        
/*        CMTime timestamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
        CVImageBufferRef frame = CMSampleBufferGetImageBuffer(sampleBuffer);
        size_t nlen = CMBlockBufferGetDataLength(CMSampleBufferGetDataBuffer(sampleBuffer));
        size_t plane_width = CVPixelBufferGetWidthOfPlane(frame, 0);
        size_t plane_height = CVPixelBufferGetHeightOfPlane(frame, 0);

        CFRelease (cm_fmt_desc);// AVSampleBufferDisplayLayer 可以投递samplebuffer 显示  
        CFRelease(sampleBuffer);
        NSLog(@"encode VideoData Output..time:%lld w:%lu h:%lu isenc:%d cnt:%llu len:%lu", timestamp.value, plane_width, plane_height, 1, mH264Cnt, nlen);
*/
//    }];
    [mConversion addTarget:mfilter];
    [mfilter addTarget:mGpuview];
    [mfilter addTarget:mRawOutput];
    [mConversion setRunBenchmark:YES];
//    [self.view addSubview:mGpuview];

    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
-(AVCaptureDevice*) getCameraDeviceWithPosition:(AVCaptureDevicePosition)position{
    NSArray *cameras = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for( AVCaptureDevice* camera in cameras){
        if( [camera position] == position ){
            return camera;
        }
    }
    return nil;
}
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    
    for ( AVCaptureInputPort *port in [connection inputPorts] )
    {
        if ( [[port mediaType] isEqual:AVMediaTypeVideo] )
        {
            CMTime timestamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
            CMFormatDescriptionRef fmt_src = CMSampleBufferGetFormatDescription(sampleBuffer);
            CVImageBufferRef frame = CMSampleBufferGetImageBuffer(sampleBuffer);
            size_t nlen = CMBlockBufferGetDataLength(CMSampleBufferGetDataBuffer(sampleBuffer));
            CVReturn status = CVPixelBufferLockBaseAddress(frame, kCVPixelBufferLock_ReadOnly);
            if (kCVReturnSuccess != status) {
                CVPixelBufferUnlockBaseAddress(frame, 0);
                frame=nil;
                return;
            }
            /*kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange*/
            size_t plane_width = CVPixelBufferGetWidthOfPlane(frame, 0);
            size_t plane_height = CVPixelBufferGetHeightOfPlane(frame, 0);
            //sanity check
            size_t y_bytePer_row = CVPixelBufferGetBytesPerRowOfPlane(frame, 0);
            size_t y_plane_height = CVPixelBufferGetHeightOfPlane(frame, 0);
            size_t y_plane_width = CVPixelBufferGetWidthOfPlane(frame, 0);
            
            size_t cbcr_plane_height = CVPixelBufferGetHeightOfPlane(frame, 1);
            size_t cbcr_plane_width = CVPixelBufferGetWidthOfPlane(frame, 1);
            size_t cbcr_bytePer_row = CVPixelBufferGetBytesPerRowOfPlane(frame, 1);
            
            uint8_t* y_src= (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(frame, 0);
            uint8_t* cbcr_src= (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(frame, 1);
            nlen = y_bytePer_row*y_plane_height + cbcr_bytePer_row*cbcr_plane_height;
//            mH264Cnt++;
//            BOOL forceKey = FALSE;
//            if( mH264Cnt%25 == 0 )
//                forceKey = TRUE;
//            BOOL isencode = [mVideoEncode encodeSampleBuffer:sampleBuffer forceKeyframe:forceKey];
//             NSLog(@"AVCapture VideoData Output....time:%lld w:%lu h:%lu isenc:%d cnt:%llu len:%lu", timestamp.value, plane_width, plane_height, 1, mH264Cnt, nlen);
            CVPixelBufferUnlockBaseAddress(frame, 0);
            CFRetain(sampleBuffer);
            dispatch_async(mbeautyq, ^{
                [mConversion processVideoSampleBuffer:sampleBuffer];
                CFRelease(sampleBuffer);
            });

        }
        if( [[port mediaType] isEqual:AVMediaTypeAudio])
        {
            CMTime timestamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
            CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
            CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
            size_t dataLength = CMBlockBufferGetDataLength(dataBuffer);
            NSLog(@"AVCapture AudioData Output....time:%lld count:%ld %lu", timestamp.value, numSamples, dataLength);
        }
    }
}
- (void)captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection NS_AVAILABLE(10_7, 6_0){
    NSLog(@"AVCapture VideoData Output..drop..");
}

-(void) viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    
    uint64_t threadid = 0;
    
    int my_err = pthread_threadid_np(pthread_self(), &threadid);
    mach_port_t id = pthread_mach_thread_np(pthread_self());
    //    thread_policy_set
    my_err = pthread_setname_np("live.test.api");
    char tname[32];
    pthread_getname_np(pthread_self(), tname, sizeof(tname));
    NSLog(@" id:%llu port:%u name:%s\n", threadid, id, tname);
    
    _capsession = [[AVCaptureSession alloc] init];
    if( [_capsession canSetSessionPreset:AVCaptureSessionPreset640x480]){// 设置分辩率
        _capsession.sessionPreset = AVCaptureSessionPreset640x480;
        NSLog(@"AVCaptureSessionPresetMedium:%@",AVCaptureSessionPreset640x480);
    }
    AVCaptureDevice *capaudiodev = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
    _capdevaudioinput = [[AVCaptureDeviceInput alloc] initWithDevice:capaudiodev error:nil];
    AVCaptureDevice *captureDevice = [self getCameraDeviceWithPosition:AVCaptureDevicePositionFront];
    if( !captureDevice ){
        NSLog(@"未获取到摄像头设置");
        return;
    }
    NSError *error = nil;
    _capdevinput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
    if( error ){
        NSLog(@"取得设置出错%@", error.localizedDescription);
        return;
    }
    // create output
    _fileout = [[AVCaptureMovieFileOutput alloc] init];
    _vdataout = [[AVCaptureVideoDataOutput alloc] init];
    [_vdataout setAlwaysDiscardsLateVideoFrames:YES];
    NSArray* fpss = [self videoSupportedFrameRateRanges:captureDevice];
    
    AVFrameRateRange *AVfrr = fpss[0];
    Float64 maxfr = [AVfrr maxFrameRate];
    Float64 minfr = [AVfrr minFrameRate];
    CMTime  maxt = [AVfrr maxFrameDuration];
    CMTime  mint = [AVfrr minFrameDuration];
    
//    _vdataout.minFrameDuration = CMTimeMake(1.0, 25.0); //Uncomment it to specify a minimum duration for each video frame
    
    dispatch_queue_t _captureQueue = dispatch_queue_create("livesdk.ios.capture.video.queue", NULL);
    [_vdataout setSampleBufferDelegate:self queue:_captureQueue];
    NSDictionary *videoSetting = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange],(NSString*)kCVPixelBufferPixelFormatTypeKey,
                                  [NSNumber numberWithUnsignedInt:9], AVVideoPixelAspectRatioHorizontalSpacingKey,
                                  [NSNumber numberWithUnsignedInt:16], AVVideoPixelAspectRatioVerticalSpacingKey,
                                  [NSNumber numberWithInt:10], AVVideoCleanApertureHorizontalOffsetKey,
                                  [NSNumber numberWithInt:25], AVVideoExpectedSourceFrameRateKey,
                                  nil];
//    kCVPixelFormatType_420YpCbCr8Planar;kCVPixelFormatType_32BGRA;kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    [_vdataout setVideoSettings:videoSetting];
    _adataout = [[AVCaptureAudioDataOutput alloc] init];
    NSDictionary *pAudioSetting = [NSDictionary dictionaryWithObjectsAndKeys:
                                   [NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
                                   [NSNumber numberWithInt:44100], AVSampleRateKey,
                                   [NSNumber numberWithInt:2], AVNumberOfChannelsKey,
                                   [NSNumber numberWithInt:16], AVLinearPCMBitDepthKey,
                                   [NSNumber numberWithBool:NO], AVLinearPCMIsFloatKey,
                                   [NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey,
                                   nil];
    dispatch_queue_t _captureAudioQueue = dispatch_queue_create("livesdk.ios.capture.audio.queue", NULL);
    [_adataout setSampleBufferDelegate:self queue:_captureAudioQueue];
//    dispatch_release(_captureAudioQueue);
    _imageout = [[AVCaptureStillImageOutput alloc] init];
    
    [_imageout setOutputSettings:@{AVVideoCodecKey: AVVideoCodecJPEG}];
    
    if( [_capsession canAddInput:_capdevinput] ){
        [_capsession addInput:_capdevinput];
    }
    if( [_capsession canAddInput:_capdevaudioinput]){
        [_capsession addInput:_capdevaudioinput];
    }
/*    if( [_capsession canAddOutput:_fileout]){
        [_capsession addOutput:_fileout];
        AVCaptureConnection *connection = [_fileout connectionWithMediaType:AVMediaTypeVideo];
//        AVCaptureVideoStabilizationMode avsm = [connection activeVideoStabilizationMode];   // 好像有防抖功能
//        if( connection.supportsVideoStabilization ){
//            [connection setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeAuto];
//        }
//        [_fileout setRecordsVideoOrientationAndMirroringChanges:YES asMetadataTrackForConnection:connection];
        // 获取对象之间的连接，并设置其方向
        AVCaptureConnection *videoConnection = NULL;
        [self.capsession beginConfiguration];
        
        for ( AVCaptureConnection *connection in [self.fileout connections] )
        {
            for ( AVCaptureInputPort *port in [connection inputPorts] )
            {
                if ( [[port mediaType] isEqual:AVMediaTypeVideo] )
                {
                    videoConnection = connection;
                }
            }
        }
        if([videoConnection isVideoOrientationSupported]) // **Here it is, its always false**
        {
            [videoConnection setVideoOrientation:AVCaptureVideoOrientationLandscapeLeft];
        }
        
        [self.capsession commitConfiguration];
    }*/
    if([_capsession canAddOutput:_vdataout]){
        [_capsession addOutput:_vdataout];
    }
    AVCaptureConnection *videoConnection = NULL;
    [self.capsession beginConfiguration];
    
    for ( AVCaptureConnection *connection in [self.vdataout connections] )
    {
        for ( AVCaptureInputPort *port in [connection inputPorts] )
        {
            if ( [[port mediaType] isEqual:AVMediaTypeVideo] )
            {
                videoConnection = connection;
            }
        }
    }
    if([videoConnection isVideoOrientationSupported]) // **Here it is, its always false**
    {
        [videoConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];//AVCaptureVideoOrientationPortrait;AVCaptureVideoOrientationLandscapeLeft
    }
    [self.capsession commitConfiguration];
/*    if([_capsession canAddOutput:_adataout]){
        [_capsession addOutput:_adataout];
    }
*/
    if([_capsession canAddOutput:_imageout]){
        [_capsession addOutput:_imageout];
    }
    
    // fps
    [self setActiveVideoMinFrameDuration:CMTimeMake(1, 25)];
    [self setActiveVideoMaxFrameDuration:CMTimeMake(1, 25)];
    
    _cap_preview_layer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_capsession];
//    if( [_cap_preview_layer isOrientationSupported])
//    [_cap_preview_layer setOrientation:AVCaptureVideoOrientationLandscapeLeft];
    _cap_preview_layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
/*    CALayer *layer = mGpuview.layer;//self.preview_cap.layer;
    layer.masksToBounds = YES;
    _cap_preview_layer.frame = layer.bounds;
    
    [layer addSublayer:_cap_preview_layer];
    [layer setBackgroundColor:[[UIColor clearColor] CGColor]];
*/
    [mGpuview setFrame: [self.preview_cap bounds]];
    [mGpuview setFillMode:kGPUImageFillModePreserveAspectRatioAndFill];
    [self.preview_cap addSubview:mGpuview];
//    [mGpuview removeFromSuperview];
//    AudioQueueNewInput(&asbd, AudioQueueInputCallback_, self, nil, nil, nil, &audioq);
    NSError *verror = 0;
    mVideoEncode = [[VTPCompressionSession alloc] initWithWidth:480 height:640 codec:kCMVideoCodecType_H264 error:&verror];
    
    BOOL issupport = [VTPCompressionSession hasHardwareSupportForCodec:kCMVideoCodecType_H264];
    NSError * seterr = NULL;
//    BOOL isset = [mVideoEncode setValue:kCFBooleanTrue forProperty:kVTCompressionPropertyKey_RealTime error:&seterr];
    BOOL isset=[mVideoEncode setRealtime:TRUE error:&seterr];
//    isset = [mVideoEncode setValue:kVTProfileLevel_H264_Main_AutoLevel forProperty:kVTCompressionPropertyKey_ProfileLevel error:&seterr];
    isset = [mVideoEncode setProfileLevel:kVTProfileLevel_H264_Baseline_AutoLevel error:&seterr];
//    isset = [mVideoEncode setValue:@25 forProperty:kVTCompressionPropertyKey_MaxKeyFrameInterval error:&seterr];
    isset = [mVideoEncode setMaxKeyframeInterval:@25 error:&seterr];
    isset = [mVideoEncode setValue:@25 forProperty:kVTCompressionPropertyKey_ExpectedFrameRate error:&seterr];
//    isset = [mVideoEncode setValue:kVTH264EntropyMode_CABAC forProperty:kVTCompressionPropertyKey_H264EntropyMode error:&seterr];
    isset = [mVideoEncode setH264EntropyMode:kVTH264EntropyMode_CAVLC error:&seterr];
//    isset = [mVideoEncode setValue:@300000 forProperty:kVTCompressionPropertyKey_AverageBitRate error:&seterr];
//    isset = [mVideoEncode setAverageBitrate:300000 error:&seterr];
    
//    isset = [mVideoEncode setValue:@30000 forProperty:kVTCompressionPropertyKey_DataRateLimits error:&seterr];
//    isset = [mVideoEncode setQuality:0.25 error:&seterr]; // low = 0.25, normal = 0.50,high = 0.75, and 1.0 implies lossless
//    kVTCompressionPropertyKey_AllowFrameReordering
//    kVTCompressionPropertyKey_Quality
    
    dispatch_queue_t encode_queue = dispatch_queue_create("livesdk.encode.video.h264", NULL);
    [mVideoEncode setDelegate:self queue:encode_queue];
    [mVideoEncode prepare];
    
    // file op
    NSString *filePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"test1.h264"];
    fdyuv = fopen([filePath cStringUsingEncoding:NSASCIIStringEncoding], "w+");
    NSString *filePath2 = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"gpu1.yuv"];
    fdgpu = fopen([filePath2 cStringUsingEncoding:NSASCIIStringEncoding], "w+");
    NSLog(@"ios version:%d",__IPHONE_OS_VERSION_MIN_REQUIRED);
}
- (void)videoCompressionSession:(VTPCompressionSession *)compressionSession didEncodeSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    CFArrayRef attachmentarr = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, TRUE);
    Boolean iskey = !CFDictionaryContainsKey(CFArrayGetValueAtIndex(attachmentarr, 0), kCMSampleAttachmentKey_NotSync);
    Boolean isDepend = (CFBooleanRef)CFDictionaryGetValue(CFArrayGetValueAtIndex(attachmentarr, 0), kCMSampleAttachmentKey_DependsOnOthers) == kCFBooleanFalse;
//    NSLog(@"depend:%d isKey:%d", isDepend, iskey);
    static int startcode = 0x01000000;
    //kCMSampleAttachmentKey_NotSync
    if( iskey ){
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t sparameterSetSize, sparameterSetCount;
        int NALUnitHeaderLengthOut1=0;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, &NALUnitHeaderLengthOut1 );
        if (statusCode == noErr)
        {
            // Found sps and now check for pps
            size_t pparameterSetSize, pparameterSetCount;
            int NALUnitHeaderLengthOut=0;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, &NALUnitHeaderLengthOut );
            if (statusCode == noErr)
            {
                // Found pps
                NSData* spsraw = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                fwrite(&startcode, sizeof(startcode), 1, fdyuv);
                fwrite(sparameterSet, sparameterSetSize, 1, fdyuv);
                NSData* ppsraw = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                fwrite(&startcode, sizeof(startcode), 1, fdyuv);
                fwrite(pparameterSet, pparameterSetSize, 1, fdyuv);
                NSLog(@"sps:%p len:%lu cnt:%lu pps:%p len:%lu cnt:%lu", sparameterSet, sparameterSetSize, sparameterSetCount, pparameterSet, pparameterSetSize, pparameterSetCount);
            }
        }
        NSLog(@"estimate byte:%llu bitrate:%llu", mEstimateBitrate, mEstimateBitrate*8);
        mEstimateBitrate = 0;
    }
    mH264EncCnt++;
    CMTime timestamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t dataLength = CMBlockBufferGetDataLength(dataBuffer);
    size_t length, totalLength;
    char * pbuf = NULL;
    CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &pbuf);
    NSLog(@"H264 Output....time:%lld  len:%lu key:%d len:%lu totallen:%lu cnt:%llu", timestamp.value, dataLength, iskey, length, totalLength, mH264EncCnt);
    mEstimateBitrate += dataLength;
    uint32_t nallen = 0;
    char* pb = pbuf;
    while( pb < (pbuf + dataLength) ){
        nallen = *((uint32_t*)pb);
        nallen = CFSwapInt32BigToHost(nallen);
        fwrite(&startcode, sizeof(startcode), 1, fdyuv);
        fwrite(pb+4, nallen, 1, fdyuv);
        pb += 4 + nallen;
    }
}

- (void)videoCompressionSession:(VTPCompressionSession *)compressionSession didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    
}
-(void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    BOOL isfinish = [mVideoEncode finish];
//    isfinish = [mVideoEncode finishUntilPresentationTimeStamp:CMTimeMake(1, 1)];
    fclose(fdyuv);
    fclose(fdgpu);
}

-(void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [self.capsession startRunning];
}
-(void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    [self.capsession stopRunning];
}
/**
 *  添加点按手势，点按时聚焦
 */
-(void)addGenstureRecognizer{
    UITapGestureRecognizer *tapGesture=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapScreen:)];
    [self.preview_cap addGestureRecognizer:tapGesture];
}
-(void)tapScreen:(UITapGestureRecognizer *)tapGesture{
    CGPoint point= [tapGesture locationInView:self.preview_cap];
    //将UI坐标转化为摄像头坐标
    CGPoint cameraPoint= [_cap_preview_layer captureDevicePointOfInterestForPoint:point];
//    [self setFocusCursorWithPoint:point];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposureMode:AVCaptureExposureModeAutoExpose atPoint:cameraPoint];
}

/**
 *  设置聚焦光标位置
 *
 *  @param point 光标位置
 */
//-(void)setFocusCursorWithPoint:(CGPoint)point{
//    self.focusCursor.center=point;
//    self.focusCursor.transform=CGAffineTransformMakeScale(1.5, 1.5);
//    self.focusCursor.alpha=1.0;
//    [UIView animateWithDuration:1.0 animations:^{
//        self.focusCursor.transform=CGAffineTransformIdentity;
//    } completion:^(BOOL finished) {
//        self.focusCursor.alpha=0;
//        
//    }];
//}
- (IBAction)capbtnclick:(id)sender {
//    AVCaptureDevice *videocapdev = [AVCaptureDevice defaultDeviceWithMediaType: AVMediaTypeVideo];
//    AVCaptureDeviceInput *capdevinput = [AVCaptureDeviceInput deviceInputWithDevice:videocapdev error:nil];
//    AVCaptureMovieFileOutput *fileout = [[AVCaptureMovieFileOutput alloc] init];
//    [_capsession addInput:capdevinput];
//    [_capsession addOutput:fileout];
//    [AVCaptureVideoPreviewLayer alloc];
//    [_capsession startRunning];
    if( [self.fileout isRecording] ){
        [self.fileout stopRecording];
    }
    else{
        NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingString:@"testMovie.mov"];
        NSLog(@"file save path :%@", outputFilePath);
        NSURL *fileurl = [NSURL fileURLWithPath:outputFilePath];
        [self.fileout startRecordingToOutputFileURL:fileurl recordingDelegate:self];
    }
    // 调整屏幕录制的方向
    AVCaptureConnection *captureConnection=[self.cap_preview_layer connection];
//    captureConnection.videoOrientation=(AVCaptureVideoOrientation)toInterfaceOrientation;
    // 调整图层显示的大小
//    _cap_preview_layer.frame=self.preview_cap.bounds;
}
- (IBAction)switchclick:(id)sender {
    AVCaptureDevice *currentDevice=[self.capdevinput device];
    AVCaptureDevicePosition currentPosition=[currentDevice position];
//    [self removeNotificationFromCaptureDevice:currentDevice];
    AVCaptureDevice *toChangeDevice;
    AVCaptureDevicePosition toChangePosition=AVCaptureDevicePositionFront;
    if (currentPosition==AVCaptureDevicePositionUnspecified||currentPosition==AVCaptureDevicePositionFront) {
        toChangePosition=AVCaptureDevicePositionBack;
    }
    toChangeDevice=[self getCameraDeviceWithPosition:toChangePosition];
//    [self addNotificationToCaptureDevice:toChangeDevice];
    //获得要调整的设备输入对象
    NSError *error;
    AVCaptureDeviceInput *toChangeDeviceInput=[[AVCaptureDeviceInput alloc]initWithDevice:toChangeDevice error:&error];
    if( error ){
        NSLog(@"取得设置出错%@", error.localizedDescription);
        return;
    }
    //改变会话的配置前一定要先开启配置，配置完成后提交配置改变
    [self.capsession beginConfiguration];
    //移除原有输入对象
    [self.capsession removeInput:self.capdevinput];
    //添加新的输入对象
    if ([self.capsession canAddInput:toChangeDeviceInput]) {
        [self.capsession addInput:toChangeDeviceInput];
        self.capdevinput=toChangeDeviceInput;
    }
    //提交会话配置
    [self.capsession commitConfiguration];
}
- (IBAction)takephoto:(UIButton *)sender {
    
    //根据设备输出获得连接
    AVCaptureConnection *captureConnection=[self.imageout connectionWithMediaType:AVMediaTypeVideo];
    [captureConnection setVideoOrientation:AVCaptureVideoOrientationPortraitUpsideDown];
    [captureConnection setVideoMirrored:true];
    //根据连接取得设备输出的数据
    [self.imageout captureStillImageAsynchronouslyFromConnection:captureConnection completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
        if (imageDataSampleBuffer) {
            NSData *imageData=[AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
            UIImage *image=[UIImage imageWithData:imageData];
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
            //            ALAssetsLibrary *assetsLibrary=[[ALAssetsLibrary alloc]init];
            //            [assetsLibrary writeImageToSavedPhotosAlbum:[image CGImage] orientation:(ALAssetOrientation)[image imageOrientation] completionBlock:nil];
        }
        
    }];
}
- (IBAction)buttonclick:(id)sender {
    NSLog(@"button click !!");
    UIImagePickerController *imagepicker = [UIImagePickerController new];
// 设置打开相册
    //    [self presentViewController:imagepicker animated:YES completion:NULL];
    // 设置打开 Camera
    if([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]){
        // 设置相机的模式
        imagepicker.sourceType = UIImagePickerControllerSourceTypeCamera;
        // 设置相册闪光灯
        imagepicker.cameraFlashMode=UIImagePickerControllerCameraFlashModeOff;
        // 设置摄像头
        imagepicker.cameraDevice=UIImagePickerControllerCameraCaptureModeVideo;
        [self presentViewController:imagepicker animated:YES completion:NULL];
    }
    else{
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"My Alert" message:@"设备不支持相机模式"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* defaultAction =
            [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {}];
        
        [alert addAction:defaultAction];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections{
    NSLog(@"开始录制...");
}
- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error{
    NSLog(@"视频录制完成.");
    //视频录入完成之后在后台将视频存储到相簿
//    self.enableRotation=YES;
//    UIBackgroundTaskIdentifier lastBackgroundTaskIdentifier=self.backgroundTaskIdentifier;
//    self.backgroundTaskIdentifier=UIBackgroundTaskInvalid;
    ALAssetsLibrary *assetsLibrary=[[ALAssetsLibrary alloc]init];
    [assetsLibrary writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
        if (error) {
            NSLog(@"保存视频到相簿过程中发生错误，错误信息：%@",error.localizedDescription);
        }
//        if (lastBackgroundTaskIdentifier!=UIBackgroundTaskInvalid) {
//            [[UIApplication sharedApplication] endBackgroundTask:lastBackgroundTaskIdentifier];
//        }
        NSLog(@"成功保存视频到相簿.");
    }];
}
typedef void(^PropertyChangeBlock)(AVCaptureDevice *captureDevice);
/**
 *  改变设备属性的统一操作方法
 *
 *  @param propertyChange 属性改变操作
 */
-(void)changeDeviceProperty:(PropertyChangeBlock)propertyChange{
    AVCaptureDevice *captureDevice= [self.capdevinput device];
    NSError *error;
    //注意改变设备属性前一定要首先调用lockForConfiguration:调用完之后使用unlockForConfiguration方法解锁
    if ([captureDevice lockForConfiguration:&error]) {
    propertyChange(captureDevice);
        [captureDevice unlockForConfiguration];
    }else{
        NSLog(@"设置设备属性过程发生错误，错误信息：%@",error.localizedDescription);
    }
}

-(NSArray*) videoSupportedFrameRateRanges:(AVCaptureDevice*) captureDevice{
    return [[captureDevice activeFormat] videoSupportedFrameRateRanges];
}

-(void)setActiveVideoMinFrameDuration:(CMTime) minFrameTime{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice){
        [captureDevice setActiveVideoMinFrameDuration:minFrameTime];
//        captureDevice.activeVideoMinFrameDuration = minFrameTime;
    }];
}

-(void)setActiveVideoMaxFrameDuration:(CMTime) minFrameTime{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice){
        [captureDevice setActiveVideoMaxFrameDuration:minFrameTime];
//        captureDevice.activeVideoMaxFrameDuration = minFrameTime;
    }];
}

/**
 *  设置闪光灯模式
 *
 *  @param flashMode 闪光灯模式
 */
-(void)setFlashMode:(AVCaptureFlashMode )flashMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFlashModeSupported:flashMode]) {
            [captureDevice setFlashMode:flashMode];
        }
    }];
}
/**
 *  设置聚焦模式
 *
 *  @param focusMode 聚焦模式
 */
-(void)setFocusMode:(AVCaptureFocusMode )focusMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:focusMode];
        }
    }];
}
/**
 *  设置曝光模式
 *
 *  @param exposureMode 曝光模式
 */
-(void)setExposureMode:(AVCaptureExposureMode)exposureMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:exposureMode];
        }
    }];
}
/**
 *  设置聚焦点
 *
 *  @param point 聚焦点
 */
-(void)focusWithMode:(AVCaptureFocusMode)focusMode exposureMode:(AVCaptureExposureMode)exposureMode atPoint:(CGPoint)point{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
        }
        if ([captureDevice isFocusPointOfInterestSupported]) {
            [captureDevice setFocusPointOfInterest:point];
        }
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:AVCaptureExposureModeAutoExpose];
        }
        if ([captureDevice isExposurePointOfInterestSupported]) {
            [captureDevice setExposurePointOfInterest:point];
        }
    }];
}

/**
 *  给输入设备添加通知
 */
-(void)addNotificationToCaptureDevice:(AVCaptureDevice *)captureDevice{
    //注意添加区域改变捕获通知必须首先设置设备允许捕获
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        captureDevice.subjectAreaChangeMonitoringEnabled=YES;
    }];
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //捕获区域发生改变
    [notificationCenter addObserver:self selector:@selector(areaChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}
-(void)removeNotificationFromCaptureDevice:(AVCaptureDevice *)captureDevice{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
}
/**
 *  移除所有通知
 */
-(void)removeNotification{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self];
}

-(void)addNotificationToCaptureSession:(AVCaptureSession *)captureSession{
    NSNotificationCenter *notificationCenter= [NSNotificationCenter defaultCenter];
    //会话出错
    [notificationCenter addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:_capsession];
}

/**
 *  设备连接成功
 *
 *  @param notification 通知对象
 */
-(void)deviceConnected:(NSNotification *)notification{
    NSLog(@"设备已连接...");
}
/**
 *  设备连接断开
 *
 *  @param notification 通知对象
 */
-(void)deviceDisconnected:(NSNotification *)notification{
    NSLog(@"设备已断开.");
}
/**
 *  捕获区域改变
 *
 *  @param notification 通知对象
 */
-(void)areaChange:(NSNotification *)notification{
    NSLog(@"捕获区域改变...");
}

/**
 *  会话出错
 *
 *  @param notification 通知对象
 */
-(void)sessionRuntimeError:(NSNotification *)notification{
    NSLog(@"会话发生错误.");
}

@end
