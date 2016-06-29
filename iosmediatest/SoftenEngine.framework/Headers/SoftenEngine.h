#import "GPUImageTwoPassTextureSamplingFilter.h"

@interface SoftenEngine : GPUImageTwoPassTextureSamplingFilter
{
}

-(void)setSoftenLevel:(float)softLevel;

- (void)render:(GPUImageFramebuffer *)srcBuf vertices:(const GLfloat *)vertices textureCoordinates:(const GLfloat *)textureCoordinates;


@end
