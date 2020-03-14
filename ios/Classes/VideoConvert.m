//
//  VideoConvert.m
//  export_video_frame
//
//  Created by wang animeng on 2019/5/24.
//

#import "VideoConvert.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import "MD5Utils.h"

typedef void(^errorBlock)(NSError *error);

@interface VideoConvert ()

@property (nonatomic,strong) NSMutableDictionary<NSString*,AVAssetWriter*> * writerQueue;

@end

@implementation VideoConvert

+ (instancetype)shared
{
    static VideoConvert *shared_ = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared_ = [[VideoConvert alloc] init];
    });
    return shared_;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.writerQueue = [[NSMutableDictionary alloc] init];
    }
    return self;
}

+ (CVPixelBufferRef)createPixelBufferRefFromUIImage:(UIImage *)image
{
    CVPixelBufferRef pxbuffer = NULL;
    CGImageRef imageRef = image.CGImage;
    size_t width = image.size.width;
    size_t height = image.size.height;
    
    NSDictionary * attributes = @{
                                  (NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{},
                                  (NSString *)kCVPixelBufferWidthKey : @(width),
                                  (NSString *)kCVPixelBufferHeightKey : @(height),
                                  (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32ARGB),
                                  };
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          width,
                                          height,
                                          kCVPixelFormatType_32ARGB,
                                          (__bridge CFDictionaryRef)attributes,
                                          &pxbuffer);
    if (status != kCVReturnSuccess || pxbuffer == NULL || imageRef == NULL) {
        return NULL;
    }
    
    EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    CIContext * ciContext = [CIContext contextWithEAGLContext:context];
    CIImage * ciImage = [[CIImage alloc] initWithImage:image];
    [ciContext render:ciImage toCVPixelBuffer:pxbuffer];
    return pxbuffer;
}

+ (void)generateResultVideoFromImageList:(NSArray *)imageList outName:(NSString*)name finished:(void (^)(NSURL *, NSError *))finishedBlock
{
    void(^handleBlock)(NSURL *, NSError *) = ^(NSURL *videoURL, NSError *error) {
        if (finishedBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                finishedBlock(videoURL, error);
            });
        }
    };
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self convertVideoByImageList:imageList outName:name fps:20  finished:^(NSURL *videoURL, NSError *error) {
            if (videoURL) {
                handleBlock(videoURL, error);
            } else {
                handleBlock(videoURL, error);
            }
        }];
    });
}

+ (NSURL *)tempVideoURL:(NSString *)name
{
    NSURL *documentURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    NSURL *tempURL = [documentURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.mov",[MD5Utils getmd5WithString:name]]];
    return tempURL;
}

+ (void)convertVideoByImageList:(NSArray *)imageList outName:(NSString *)name fps:(int32_t)fps finished:(void (^)(NSURL *videoURL, NSError *error))finishedBlock
{
    errorBlock errorHandle = ^(NSError *error){
        if (finishedBlock) {
            finishedBlock(nil, error);
        }
    };
    __block NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *videoURL = [self tempVideoURL:name];
    // if video URL exits, return
    if ([fileManager fileExistsAtPath:videoURL.path]) {
        if (finishedBlock) {
            finishedBlock(videoURL, nil);
        }
        return;
    }
    
    CGSize imageSize = [(UIImage *)imageList.firstObject size];
    // AVAsset Writer
    AVAssetWriter *videoWriter = [[AVAssetWriter alloc] initWithURL:videoURL fileType:AVFileTypeMPEG4 error:&error];
    // fix bug: iOS8下，防止videoWrite过早被释放掉导致completeBlock不能调用
    
    [[VideoConvert shared].writerQueue setObject:videoWriter forKey:name];
    if (error) {
        NSLog(@"AVAssetWriter init failed: %@", error);
        errorHandle(error);
        return;
    }
    NSDictionary *setting = @{
                              AVVideoCodecKey: AVVideoCodecH264,
                              AVVideoWidthKey: @(imageSize.width),
                              AVVideoHeightKey: @(imageSize.height),
                              AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
                              };
    AVAssetWriterInput *videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:setting];
    NSDictionary *pixelBufferAttributes = @{
                                            (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey : @YES,
                                            (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES,
                                            (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32ARGB),
                                            };
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoWriterInput sourcePixelBufferAttributes:pixelBufferAttributes];
    videoWriterInput.expectsMediaDataInRealTime = NO;
    
    if (![videoWriter canAddInput:videoWriterInput]) {
        NSLog(@"video writer can't add video writer input!");
        error = [NSError errorWithDomain:@"GFVideoWriterErrorDomain" code:-10020 userInfo:@{NSLocalizedDescriptionKey: @"视频写入初始化失败!"}];
        errorHandle(error);
        return;
    }
    [videoWriter addInput:videoWriterInput];
    
    //Start a session:
    [videoWriter startWriting];
    [videoWriter startSessionAtSourceTime:kCMTimeZero];
    
    __block NSInteger currentIndex = 0;
    dispatch_queue_t writerQueue = dispatch_queue_create("GFVideoWriterQueue", DISPATCH_QUEUE_SERIAL);
    [videoWriterInput requestMediaDataWhenReadyOnQueue:writerQueue usingBlock:^{
        while ([videoWriterInput isReadyForMoreMediaData]) {
            if (currentIndex < imageList.count) {
                CVPixelBufferRef buffer = [self createPixelBufferRefFromUIImage:imageList[currentIndex%imageList.count]];
                CMTime frameTime = CMTimeMake(currentIndex, fps);
                if (videoWriterInput.isReadyForMoreMediaData) {
                    BOOL appendOK = [adaptor appendPixelBuffer:buffer withPresentationTime:frameTime];
                    CVPixelBufferRelease(buffer);
                    buffer = NULL;
                    NSLog(@"append frame: %@ success?: %@", @(currentIndex), @(appendOK));
                    if (!appendOK && videoWriter.status == AVAssetWriterStatusFailed) {
                        error = videoWriter.error;
                        if (finishedBlock) {
                            finishedBlock(nil, error);
                            [[VideoConvert shared].writerQueue removeObjectForKey:name];
                            return;
                        }
                    }
                    currentIndex++;
                }
            } else {
                [videoWriterInput markAsFinished];
                [videoWriter finishWritingWithCompletionHandler:^{
                    NSLog(@"video write ended.");
                    if (finishedBlock) {
                        finishedBlock(videoURL, nil);
                    }
                    [[VideoConvert shared].writerQueue removeObjectForKey:name];
                }];
            }
        }
    }];
}

@end
