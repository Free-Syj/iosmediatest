//
//  GPUImageRawDirectDataOutput.h
//  iosmediatest
//
//  Created by sks on 16/6/22.
//  Copyright © 2016年 sks. All rights reserved.
//
#ifdef __MACH__
#include <sys/types.h>
#include <sys/timeb.h>
#endif
typedef struct ortpTimeSpec{
    int64_t tv_sec;
    int64_t tv_nsec;
}ortpTimeSpec;

void ortp_get_cur_time(ortpTimeSpec *ret);
uint64_t get_wallclock_ms(void);
#define TIMECHECKBEGIN(name) \
ortpTimeSpec name##_begin, name##_end;	\
ortp_get_cur_time(&name##_begin)
#define TIMECHECKEND(name, nlimit, sformat, ...)	\
ortp_get_cur_time(&name##_end);	\
int64_t name##_dprocesstime = ((name##_end.tv_sec - name##_begin.tv_sec)*1000.0 + \
(name##_end.tv_nsec - name##_begin.tv_nsec) / 1000000.0);	\
if( name##_dprocesstime > nlimit )	\
{	\
NSLog(@"%s time-check:%lld " sformat, __func__, name##_dprocesstime, ## __VA_ARGS__);	\
}

#import "GPUImageContext.h"

@interface GPUImageRawDirectDataOutput : NSObject <GPUImageInput>

@property(readonly) GLubyte *rawBytesForImage;
@property(nonatomic, copy) void(^newFrameAvailableBlock)(void);

-(id)initWithImageSize:(CGSize)newImageSize;
// Data access
- (NSUInteger)bytesPerRowInOutput;
- (void)setImageSize:(CGSize)newImageSize;
-(GLubyte*)rawBytesForYuv420p;
-(GLubyte*)rawBytesForYuvNv12;
-(CMSampleBufferRef)rawBytesForSampleBuffer;
-(CMSampleBufferRef)rawBytesGpuForSampleBuffer;
-(CVPixelBufferRef)rawBytesGpuForPixelBuffer;
-(CVPixelBufferRef)rawBytesy420ForPixelBuffer;
-(CVPixelBufferRef)rawBytesnv12ForPixelBuffer;
@end
