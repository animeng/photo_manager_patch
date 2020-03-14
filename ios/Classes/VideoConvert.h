//
//  VideoConvert.h
//  export_video_frame
//
//  Created by wang animeng on 2019/5/24.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VideoConvert : NSObject

+ (void)generateResultVideoFromImageList:(NSArray *)imageList outName:(NSString*)name finished:(void (^)(NSURL *, NSError *))finishedBlock;

@end

NS_ASSUME_NONNULL_END
