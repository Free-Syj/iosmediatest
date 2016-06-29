//
//  AudioQueueViewController.m
//  iosmediatest
//
//  Created by sks on 16/5/31.
//  Copyright © 2016年 sks. All rights reserved.
//

#import "AudioQueueViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AudioToolbox/AudioFile.h>
@interface AudioQueueViewController (){
    AudioStreamBasicDescription m_audiostreambasicdesc;
    AudioQueueRef               m_audioqueueref;
    bool                        m_IsRunning;
    AudioFileID                 mAudioFile;
    SInt64                       mCurrentPacket;
    UInt32                      BufferSize;
}
@property (weak, nonatomic) IBOutlet UIButton *AudioQueueStart;
@property (weak, nonatomic) IBOutlet UIButton *AudioQueueStop;

@end

@implementation AudioQueueViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
void _AudioQueueInputCallback (void                                 *aqData,
                               AudioQueueRef                        inAQ,
                               AudioQueueBufferRef                  inBuffer,
                               const AudioTimeStamp                 *inStartTime,
                               UInt32                               inNumPackets,
                               const AudioStreamPacketDescription   *inPacketDesc )
{
    AudioQueueViewController *pAqData = (__bridge AudioQueueViewController *) aqData;
    
    if (inNumPackets == 0 &&
        pAqData->m_audiostreambasicdesc.mBytesPerPacket != 0)
        inNumPackets =
        inBuffer->mAudioDataByteSize / pAqData->m_audiostreambasicdesc.mBytesPerPacket;
    NSLog(@"size:%ld packet:%lu time:%f", inBuffer->mAudioDataByteSize, inNumPackets, inStartTime->mSampleTime);
    OSStatus nre=0;
    if ((nre=AudioFileWritePackets (
                               pAqData->mAudioFile,
                               false,
                               inBuffer->mAudioDataByteSize,
                               inPacketDesc,
                               pAqData->mCurrentPacket,
                               &inNumPackets,
                               inBuffer->mAudioData
                               )) == noErr) {
        pAqData->mCurrentPacket += inNumPackets;
    }
    
    if (pAqData->m_IsRunning == 0)
        return;
    
    OSStatus nret=AudioQueueEnqueueBuffer (
                             pAqData->m_audioqueueref,
                             inBuffer,
                             0,
                             NULL
                             );
}

-(void)viewWillAppear:(BOOL)animated{
    Float64 hardwareSampleRate=0;
    UInt32 propertySize = sizeof (hardwareSampleRate);
    AudioSessionGetProperty (kAudioSessionProperty_CurrentHardwareSampleRate,&propertySize,&hardwareSampleRate);
#if TARGET_IPHONE_SIMULATOR
    m_audiostreambasicdesc.mSampleRate = 44100.0;
#warning *** Simulator mode: using 44.1 kHz sample rate.
#else
    m_audiostreambasicdesc.mSampleRate = hardwareSampleRate;
#endif
    
    NSLog (@"Hardware sample rate = %f", m_audiostreambasicdesc.mSampleRate);
//    kAudioFormatMPEG4AAC
    AudioFormatID formatID = kAudioFormatMPEG4AAC;
    m_audiostreambasicdesc.mFormatID           = formatID;
    m_audiostreambasicdesc.mChannelsPerFrame   = 1;  // channel
    
    if (formatID == kAudioFormatLinearPCM) {
        
        m_audiostreambasicdesc.mFormatFlags        = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        m_audiostreambasicdesc.mBitsPerChannel     = 16;   // sample_of_bits 精度
        m_audiostreambasicdesc.mBytesPerFrame      = m_audiostreambasicdesc.mChannelsPerFrame * m_audiostreambasicdesc.mBitsPerChannel/8; // 每帧大小
        
        m_audiostreambasicdesc.mFramesPerPacket    = 1; // 每个数据包的帧数
        m_audiostreambasicdesc.mBytesPerPacket     = m_audiostreambasicdesc.mFramesPerPacket * m_audiostreambasicdesc.mBytesPerFrame; // 每个数据包的字节数
        
    }
    if (formatID == kAudioFormatMPEG4AAC ){
//        m_audiostreambasicdesc.mFormatFlags        = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
//        m_audiostreambasicdesc.mBitsPerChannel     = 32;   // sample_of_bits 精度
//        m_audiostreambasicdesc.mBytesPerFrame      = m_audiostreambasicdesc.mChannelsPerFrame * m_audiostreambasicdesc.mBitsPerChannel/8; // 每帧大小
//
//        m_audiostreambasicdesc.mFramesPerPacket    = 1; // 每个数据包的帧数
//        m_audiostreambasicdesc.mBytesPerPacket     = m_audiostreambasicdesc.mFramesPerPacket * m_audiostreambasicdesc.mBytesPerFrame; // 每个数据包的字节数
    }
    OSStatus result = 0;
    result =   AudioQueueNewInput (&m_audiostreambasicdesc,
                                            _AudioQueueInputCallback,
                                            (__bridge void * _Nullable)(self),                   // userData
                                            NULL,                   // run loop
                                            NULL,                   // run loop mode
                                            0,                      // flags
                                            &m_audioqueueref);
    NSLog (@"Attempted to create new recording audio queue object. Result: %ld", result);
    UInt32 sizeOfRecordingFormatASBDStruct = sizeof (m_audiostreambasicdesc);
    result=AudioQueueGetProperty (m_audioqueueref,
                           kAudioQueueProperty_StreamDescription,  // this constant is only available in iPhone OS
                           &m_audiostreambasicdesc,
                           &sizeOfRecordingFormatASBDStruct);
    // calc buffer size
    static const int maxBufferSize = 0x50000;
    UInt32 maxPacketSize = 0;
    UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
    
    result = AudioQueueGetProperty (m_audioqueueref,
                        kAudioQueueProperty_MaximumOutputPacketSize,
                       &maxPacketSize,
                       &maxVBRPacketSize);
    
    Float64 seconds = 0.04;
    Float64 numBytesForTime = m_audiostreambasicdesc.mSampleRate * maxPacketSize * seconds;
    BufferSize = maxPacketSize;//(UInt32) (numBytesForTime < maxBufferSize ? numBytesForTime : maxBufferSize);
    // add
/*    int kNumberBuffers = 3;
    AudioQueueBufferRef buffers[kNumberBuffers];
    for (int i = 0; i < kNumberBuffers; ++i) {
        AudioQueueAllocateBuffer (m_audioqueueref,
                                  BufferSize,
                                  &buffers[i]
                                  );
        
        result=AudioQueueEnqueueBuffer (
                                 m_audioqueueref,
                                 buffers[i],
                                 0,
                                 NULL
                                 );
    }
    */
    // open file
    NSString *filePath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"test1.adts"];
    CFURLRef audioFileURL = CFURLCreateFromFileSystemRepresentation (NULL,
                                             (const UInt8 *) [filePath cStringUsingEncoding:[NSString defaultCStringEncoding]],
                                             strlen ([filePath cStringUsingEncoding:[NSString defaultCStringEncoding]]),
                                             false );
    AudioFileTypeID fileType             = kAudioFileAAC_ADTSType;
    OSStatus re=AudioFileCreateWithURL (audioFileURL,
                            fileType,
                            &m_audiostreambasicdesc,
                            kAudioFileFlags_EraseFile,
                            &mAudioFile);

}
-(void)viewWillDisappear:(BOOL)animated{
    AudioQueueDispose (
                       m_audioqueueref,
                       true                         
                       );
    
    AudioFileClose (mAudioFile);
}
- (IBAction)AudioQueueStartAction:(id)sender {
    
    
     int kNumberBuffers = 3;
     AudioQueueBufferRef buffers[kNumberBuffers];
     for (int i = 0; i < kNumberBuffers; ++i) {
     AudioQueueAllocateBuffer (m_audioqueueref,
     BufferSize,
     &buffers[i]
     );
     
     OSStatus result=AudioQueueEnqueueBuffer (
     m_audioqueueref,
     buffers[i],
     0,
     NULL
     );
     }
     
    m_IsRunning = true;
    OSStatus re=AudioQueueStart (m_audioqueueref,
                     NULL );
}
- (IBAction)AudioQueueStopAction:(id)sender {
    // Wait, on user interface thread, until user stops the recording
    AudioQueueStop ( m_audioqueueref,
                    true);
    m_IsRunning = false;
    AudioQueuePause(m_audioqueueref);
}

@end
