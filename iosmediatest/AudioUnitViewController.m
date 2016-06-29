//
//  AudioUnitViewController.m
//  iosmediatest
//
//  Created by sks on 16/5/31.
//  Copyright © 2016年 sks. All rights reserved.
//

#import "AudioUnitViewController.h"
#import <AudioUnit/AudioUnit.h>
@interface AudioUnitViewController (){
    AudioComponentDescription mAcdesc;

    AudioUnit                 mAunit;
}
@property (weak, nonatomic) IBOutlet UIButton *AudioUnitStart;
@property (weak, nonatomic) IBOutlet UIButton *AudioUnitStop;

@end

@implementation AudioUnitViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}
OSStatus _AURenderCallback(	void *							inRefCon,
                    AudioUnitRenderActionFlags *	ioActionFlags,
                    const AudioTimeStamp *			inTimeStamp,
                    UInt32							inBusNumber,
                    UInt32							inNumberFrames,
                    AudioBufferList * __nullable	ioData){
    AudioUnitViewController * sself = (__bridge AudioUnitViewController *)(inRefCon);

    AudioBuffer buffer;
    buffer.mData = NULL;
    buffer.mDataByteSize = 0;
    buffer.mNumberChannels = 2;
    
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0] = buffer;
    OSStatus status = AudioUnitRender(sself->mAunit,ioActionFlags,inTimeStamp,inBusNumber,inNumberFrames,&bufferList);
    AudioBuffer buf = bufferList.mBuffers[0];
    NSLog(@"size:%lu ch:%lu num:%lu-%lu bus:%lu time:%lf",buf.mDataByteSize, buf.mNumberChannels, bufferList.mNumberBuffers, inNumberFrames, inBusNumber, inTimeStamp->mSampleTime);

    return noErr;
}
-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    mAcdesc.componentType = kAudioUnitType_Output;
    mAcdesc.componentSubType = kAudioUnitSubType_RemoteIO;
    mAcdesc.componentFlags = 0;
    mAcdesc.componentFlagsMask = 0;
    mAcdesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &mAcdesc);
    
    OSStatus nre = AudioComponentInstanceNew(inputComponent, &mAunit);
    UInt32 flag = 1;
    OSStatus status = AudioUnitSetProperty(mAunit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  1,
                                  &flag,
                                  sizeof(flag));
    AudioStreamBasicDescription audioFormat;
    audioFormat.mSampleRate = 44100.00;
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioFormat.mChannelsPerFrame = 2;
    audioFormat.mBitsPerChannel = 16;
    audioFormat.mBytesPerFrame = audioFormat.mChannelsPerFrame * audioFormat.mBitsPerChannel/8;
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mBytesPerPacket = audioFormat.mFramesPerPacket * audioFormat.mBytesPerFrame;
    
    status = AudioUnitSetProperty(mAunit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  1,
                                  &audioFormat,
                                  sizeof(audioFormat));
    
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = _AURenderCallback;
    callbackStruct.inputProcRefCon = (__bridge void * _Nullable)(self);
    status = AudioUnitSetProperty(mAunit,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global,
                                  1,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    AudioUnitInitialize(mAunit);
}
-(void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
//    AudioComponentInstanceDispose(mAunit);
    AudioUnitUninitialize(mAunit);
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}
- (IBAction)AudioUnitStart:(id)sender {
    AudioOutputUnitStart(mAunit);
}
- (IBAction)AudioUnitStop:(id)sender {
    AudioOutputUnitStop(mAunit);
}
@end
