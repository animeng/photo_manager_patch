//
//  UIImage+Gif.h
//  export_video_frame
//
//  Created by wang animeng on 2019/5/24.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIImage (Gif)

+ (NSArray *)imagesGifData:(NSData *)data;

+ (NSArray *)imagesGifURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
