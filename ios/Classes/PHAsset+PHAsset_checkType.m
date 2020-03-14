//
//  PHAsset+PHAsset_checkType.m
//  photo_manager
//
//  Created by Caijinglong on 2018/10/11.
//

#import "PHAsset+PHAsset_checkType.h"

@implementation PHAsset (PHAsset_checkType)

-(bool)isImage{
    return [self mediaType] == PHAssetMediaTypeImage;
}

-(bool)isLivePhoto{
    return self.mediaSubtypes & PHAssetMediaSubtypePhotoLive;
}

-(bool)isGif{
    if ([self mediaType] != PHAssetMediaTypeImage) {
        return NO;
    }
    __block BOOL isGIFImage = NO;
    NSArray *resourceList = [PHAssetResource assetResourcesForAsset:self];
    [resourceList enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        PHAssetResource *resource = obj;
        if ([resource.uniformTypeIdentifier isEqualToString:@"com.compuserve.gif"]) {
            isGIFImage = YES;
        }
    }];
    return isGIFImage;
}

-(bool)isVideo{
    return [self mediaType] == PHAssetMediaTypeVideo;
}

-(bool)isImageOrVideo{
    return [self isVideo] || [self isImage];
}

@end
