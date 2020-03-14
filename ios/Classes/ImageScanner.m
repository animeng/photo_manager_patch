//
// Created by Caijinglong on 2018/9/10.
//
#import "ImageScanner.h"
#import <Flutter/FlutterChannels.h>
#import <Photos/PHAsset.h>
#import <Photos/PHCollection.h>
#import <Photos/Photos.h>
#import <Photos/PHFetchOptions.h>
#import <Photos/PHImageManager.h>
#import <Photos/PHPhotoLibrary.h>
#import <Foundation/Foundation.h>
#import "MD5Utils.h"
#import "PHAsset+PHAsset_checkType.h"
#import "AssetEntity.h"
#import "Reply.h"
#import "PhotoChangeObserver.h"
#import "UIImage+Gif.h"
#import "VideoConvert.h"

@interface ImageScanner ()

@property(nonatomic, strong) NSMutableDictionary<NSString *, PHAssetCollection *> *albumCollection;
// key是相册的id
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSArray<PHAsset *> *> *albumAssetDict;

@property (nonatomic, strong) NSMutableDictionary<NSString * ,PHAsset *> * assetDict;

@property(nonatomic) dispatch_queue_t asyncQueue;

@property(nonatomic, strong) PhotoChangeObserver *observer;

@end

@implementation ImageScanner {
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.albumCollection = [NSMutableDictionary new];
        self.assetDict = [NSMutableDictionary new];
        self.albumAssetDict = [NSMutableDictionary new];
        self.asyncQueue = dispatch_queue_create("asyncQueue", nil);
        self.observer = [PhotoChangeObserver new];
    }

    return self;
}

- (void)scanAlbum:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_asyncQueue, ^{
        [self refreshGallery];
        dispatch_async(dispatch_get_main_queue(), ^{
            result(@YES);
        });
    });
}

- (void)requestPermissionWithResult:(FlutterResult)result {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized) {
            [self.observer initWithRegister:self.registrar];
            result(@1);
        } else {
            result(@0);
        }
    }];

}

- (void)getGalleryIdList:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_asyncQueue, ^{
        BOOL cached = [call.arguments boolValue];
        if (!cached) {
            [self refreshGallery];
        }
        result(self.albumCollection.allKeys);
    });
}

- (void)refreshGallery {
    if (self.albumCollection.count > 0) {
        [self.albumCollection removeAllObjects];
    }
    if (self.assetDict.count > 0) {
        [self.assetDict removeAllObjects];
    }
    if (self.albumAssetDict.count > 0) {
        [self.albumAssetDict removeAllObjects];
    }

    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];

    PHFetchResult *smartAlbumsFetchResult =
            [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum
                                                     subtype:PHAssetCollectionSubtypeSmartAlbumUserLibrary
                                                     options:nil];
    // 相机相册
    PHAssetCollection *collection = [smartAlbumsFetchResult objectAtIndex:0];
    self.albumCollection[collection.localIdentifier] = collection;

    // 用户自己创建的相册
    PHFetchResult *smartAlbumsFetchResult1 =
            [PHAssetCollection fetchTopLevelUserCollectionsWithOptions:fetchOptions];
    for (PHAssetCollection *sub in smartAlbumsFetchResult1) {
        if (![collection isKindOfClass:[PHAssetCollection class]]) continue;
        
        self.albumCollection[sub.localIdentifier] = sub;
    }
    
    // 获取PHAsset
    PHFetchOptions *opt = [PHFetchOptions new];
    
    for (PHAssetCollection *collection in self.albumCollection.allValues) {
        if (![collection isKindOfClass:[PHAssetCollection class]]) continue;
        PHFetchResult<PHAsset *> *assetResult = [PHAsset
                                                 fetchAssetsInAssetCollection:collection
                                                 options:opt];
        NSMutableSet * allAssets = [NSMutableSet set];
        for (PHAsset *asset in assetResult) {
            self.assetDict[asset.localIdentifier] = asset;
            [allAssets addObject:asset];
        }
        self.albumAssetDict[collection.localIdentifier] = allAssets.allObjects;
    }
    
}

- (void)filterAssetWithBlock:(asset_block)block {
    if (self.assetDict.count > 0) {
        NSArray * albumIds = self.albumAssetDict.allKeys;
        for (NSString * collectId in albumIds) {
            NSArray * assets = self.albumAssetDict[collectId];
            for (PHAsset * asset in assets) {
                block(self.albumCollection[collectId],asset);
            }
        }
    }
}

- (void)getGalleryNameWithCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_asyncQueue, ^{
        NSArray *ids = call.arguments;
        NSMutableArray *names = [NSMutableArray new];
        for (NSString *cId in ids) {
            PHCollection *collection = self.albumCollection[cId];
            if (collection) {
                [names addObject:collection.localizedTitle];
            } else {
                [names addObject:@"Default"];
            }
        }
        result(names);
    });
}

- (void)getImageListWithCall:(FlutterMethodCall *)call result:(FlutterResult)flutterResult {
    dispatch_async(_asyncQueue, ^{

        NSString *albumId = call.arguments;
        NSArray *fetchResult = self.albumAssetDict[albumId];

        NSMutableArray * assetIds = [NSMutableArray new];
        for (PHAsset *asset in fetchResult) {
            NSString *assetId = asset.localIdentifier;
            [assetIds addObject:assetId];
        }

        flutterResult(assetIds);
    });
}

- (void)forEachAssetCollection:(FlutterMethodCall *)call result:(FlutterResult)flutterResult {
    dispatch_async(_asyncQueue, ^{
        flutterResult(self.assetDict.allValues);
    });
}

- (void)getThumbPathWithCall:(FlutterMethodCall *)call result:(FlutterResult)flutterResult {
    dispatch_async(_asyncQueue, ^{
        PHImageManager *manager = PHImageManager.defaultManager;

        NSString *imgId = call.arguments;

        PHAsset *asset = self.assetDict[imgId];

        [manager requestImageForAsset:asset
                           targetSize:CGSizeMake(100, 100)
                          contentMode:PHImageContentModeAspectFill
                              options:[PHImageRequestOptions new]
                        resultHandler:^(UIImage *result, NSDictionary *info) {

                            BOOL downloadFinined =
                                    ![[info objectForKey:PHImageCancelledKey] boolValue] &&
                                            ![info objectForKey:PHImageErrorKey] &&
                                            ![[info objectForKey:PHImageResultIsDegradedKey] boolValue];
                            if (!downloadFinined) {
                                flutterResult(nil);
                                return;
                            }

                            NSData *data = UIImageJPEGRepresentation(result, 95);
                            NSString *path = [self writeThumbFileWithAssetId:asset imageData:data];
                            flutterResult(path);
                        }];
    });
}

- (void)getThumbBytesWithCall:(FlutterMethodCall *)call result:(FlutterResult)flutterResult reply:(Reply *)reply {
    dispatch_async(_asyncQueue, ^{
        PHImageManager *manager = PHImageManager.defaultManager;

        NSArray *args = call.arguments;
        NSString *imgId = [args objectAtIndex:0];
        int width = [((NSString *) [args objectAtIndex:1]) intValue];
        int height = [((NSString *) [args objectAtIndex:2]) intValue];
        // NSLog(@"request width = %i , height = %i",width,height);

        PHAsset *asset = self.assetDict[imgId];
        PHImageRequestOptions *options = [PHImageRequestOptions new];
        options.resizeMode = PHImageRequestOptionsResizeModeFast;
        [options setNetworkAccessAllowed:YES];
        [options setProgressHandler:^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
            if (progress != 1.0) {
                return;
            }
            [self getThumbBytesWithCall:call result:flutterResult reply:reply];
        }];
        
        [manager requestImageForAsset:asset
                           targetSize:CGSizeMake(width, height)
                          contentMode:PHImageContentModeAspectFill
                              options:options
                        resultHandler:^(UIImage *result, NSDictionary *info) {
                            BOOL downloadFinined =
                                    ![[info objectForKey:PHImageCancelledKey] boolValue] &&
                                            ![info objectForKey:PHImageErrorKey] &&
                                            ![[info objectForKey:PHImageResultIsDegradedKey] boolValue];
                            if (!downloadFinined) {
                                return;
                            }
                            NSData *data = UIImageJPEGRepresentation(result, 100);

                            if (reply.isReply) {
                                return;
                            }

                            reply.isReply = YES;

                            if (!data) {
                                flutterResult([FlutterStandardTypedData typedDataWithBytes:[NSData new]]);
                                return;
                            }

                            FlutterStandardTypedData *typedData = [FlutterStandardTypedData typedDataWithBytes:data];
                            flutterResult(typedData);
                        }];
    });
}

- (NSString *)writeThumbFileWithAssetId:(PHAsset *)asset imageData:(NSData *)imageData {
    NSString *homePath = NSTemporaryDirectory();

    NSFileManager *manager = NSFileManager.defaultManager;

    NSMutableString *path = [NSMutableString stringWithString:homePath];
    NSString *dir = [path stringByAppendingPathComponent:@".thumb"];
    if (![manager fileExistsAtPath:dir]) {
        [manager createDirectoryAtPath:dir withIntermediateDirectories:NO attributes:NULL error:NULL];
    }

    NSMutableString *p = [[NSMutableString alloc] initWithString:dir];
    NSString *filePath = [p
            stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@.jpg", [MD5Utils getmd5WithString:asset.localIdentifier]]];
    if ([manager fileExistsAtPath:filePath]) {
        return filePath;
    }

    return filePath;
}

- (void)getFullFileWithCall:(FlutterMethodCall *)call result:(FlutterResult)flutterResult reply:(Reply *)reply {

    NSDictionary *params = [call arguments];

    dispatch_async(_asyncQueue, ^{
        PHImageManager *manager = PHImageManager.defaultManager;
        BOOL isOri = [params[@"isOrigin"] boolValue];
        NSString *imgId = params[@"id"];

        PHAsset *asset = self.assetDict[imgId];
        __weak ImageScanner *wSelf = self;
        if (asset.isGif) {
            [self videoUrlForGifAsset:asset withCompletionBlock:^(NSString *path) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    flutterResult(path);
                });
            }];
        } else if (asset.isLivePhoto) {
            [self videoUrlForLivePhotoAsset:asset withCompletionBlock:^(NSString *path) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    flutterResult(path);
                });
            }];
        } else if ([asset isImage]) {
            PHImageRequestOptions *options = [PHImageRequestOptions new];
            options.resizeMode = PHImageRequestOptionsResizeModeFast;

            [options setProgressHandler:^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
                if (progress == 1.0) {
                    [self getFullFileWithCall:call result:flutterResult reply:reply];
                }
            }];

            if (!isOri) {
                [manager requestImageForAsset:asset targetSize:CGSizeMake(asset.pixelWidth, asset.pixelHeight) contentMode:PHImageContentModeAspectFill options:options resultHandler:^(UIImage *result, NSDictionary *info) {
                    BOOL downloadFinish = [self isFinishWithInfo:info];
                    if (!downloadFinish) {
                        return;
                    }
                    NSData *data = UIImageJPEGRepresentation(result, 100);

                    if (reply.isReply) {
                        return;
                    }

                    reply.isReply = YES;

                    reply.isReply = YES;

                    NSString *path = [wSelf writeFullFileWithAssetId:asset imageData:data postfix:@"_origin"];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        flutterResult(path);
                    });
                }];
            } else {
                [manager requestImageDataForAsset:asset options:options resultHandler:^(NSData *imageData, NSString *dataUTI,
                        UIImageOrientation orientation, NSDictionary *info) {

                    BOOL downloadFinined = [self isFinishWithInfo:info];
                    if (!downloadFinined) {
                        return;
                    }

                    if (reply.isReply) {
                        return;
                    }

                    reply.isReply = YES;

                    NSString *path = [wSelf writeFullFileWithAssetId:asset imageData:imageData postfix:@"_exif"];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        flutterResult(path);
                    });
                }];
            }
        } else if ([asset isVideo]) {
            [self writeFullVideoFileWithAsset:asset result:flutterResult reply:reply];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                flutterResult(nil);
            });
        }
    });
}

- (BOOL)isFinishWithInfo:(NSDictionary *)info {
    return ![info[PHImageCancelledKey] boolValue] &&
            !info[PHImageErrorKey] &&
            ![info[PHImageResultIsDegradedKey] boolValue];
}

- (void)writeFullVideoFileWithAsset:(PHAsset *)asset result:(FlutterResult)result reply:(Reply *)reply {
    dispatch_async(_asyncQueue, ^{
        NSString *homePath = NSTemporaryDirectory();
        NSFileManager *manager = NSFileManager.defaultManager;

        NSMutableString *path = [NSMutableString stringWithString:homePath];

        NSString *filename = [asset valueForKey:@"filename"];

        NSString *dirPath = [NSString stringWithFormat:@"%@/%@", homePath, @".video"];
        if (![manager fileExistsAtPath:dirPath]) {
            [manager createDirectoryAtPath:dirPath withIntermediateDirectories:NO attributes:NULL error:NULL];
        }

        [path appendFormat:@"%@/%@", @".video", filename];
        PHVideoRequestOptions *options = [PHVideoRequestOptions new];
        if ([manager fileExistsAtPath:path]) {
            NSLog(@"read cache from %@", path);
            reply.isReply = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                result(path);
            });
            return;
        }

        [options setProgressHandler:^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
            if (progress == 1.0) {
                [self writeFullVideoFileWithAsset:asset result:result reply:reply];
            }
        }];

        [options setNetworkAccessAllowed:YES];
        options.version = PHVideoRequestOptionsVersionOriginal;

        [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset *_Nullable asset, AVAudioMix *_Nullable audioMix,
                NSDictionary *_Nullable info) {

            BOOL downloadFinined =
                    ![info[PHImageCancelledKey] boolValue] &&
                            !info[PHImageErrorKey] &&
                            ![info[PHImageResultIsDegradedKey] boolValue];
            if (!downloadFinined) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    result(nil);
                });
                return;
            }

            if (reply.isReply) {
                return;
            }
            
            if (![asset isKindOfClass:[AVURLAsset class]]) {
                return;
            }

            reply.isReply = YES;
            NSURL *fileRUL = [asset valueForKey:@"URL"];
            NSData *beforeVideoData = [NSData dataWithContentsOfURL:fileRUL];  //未压缩的视频流
            BOOL createResult = [manager createFileAtPath:path contents:beforeVideoData attributes:@{}];
            NSLog(@"write file to %@ , size = %lu , createResult = %@", path,
                    (unsigned long) beforeVideoData.length, createResult ? @"true" : @"false");
            dispatch_async(dispatch_get_main_queue(), ^{
                result(path);
            });
        }];
    });
}

- (NSString *)writeFullFileWithAssetId:(PHAsset *)asset imageData:(NSData *)imageData postfix:(NSString *)postfix {
    NSString *homePath = NSTemporaryDirectory();
    NSFileManager *manager = NSFileManager.defaultManager;

    NSMutableString *path = [NSMutableString stringWithString:homePath];
    [path appendString:@".images"];

    if (![manager fileExistsAtPath:path]) {
        [manager createDirectoryAtPath:path withIntermediateDirectories:NO attributes:NULL error:NULL];
    }

    [path appendString:@"/"];
    [path appendString:[MD5Utils getmd5WithString:asset.localIdentifier]];
    if (postfix) {
        [path appendString:postfix];
    }
    [path appendString:@".jpg"];

    if ([manager fileExistsAtPath:path]) {
        return path;
    }

    [manager createFileAtPath:path contents:imageData attributes:@{}];
    return path;
}

- (void)getBytesWithCall:(FlutterMethodCall *)call result:(FlutterResult)flutterResult reply:(Reply *)reply {
    dispatch_async(_asyncQueue, ^{
        NSString *imgId = call.arguments;
        PHAsset *asset = self.assetDict[imgId];

        PHImageManager *manager = PHImageManager.defaultManager;
        PHImageRequestOptions *options = [PHImageRequestOptions new];
        [options setNetworkAccessAllowed:YES];
        [options setProgressHandler:^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
            if (progress == 1.0) {
                [self getBytesWithCall:call result:flutterResult reply:reply];
            }
        }];
        [manager requestImageDataForAsset:asset options:options resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {

            BOOL downloadFinined =
                    ![info[PHImageCancelledKey] boolValue] &&
                            !info[PHImageErrorKey] &&
                            ![info[PHImageResultIsDegradedKey] boolValue];
            if (!downloadFinined) {
                flutterResult(nil);
                return;
            }

            if (reply.isReply) {
                return;
            }

            reply.isReply = YES;

            NSArray *arr = [ImageScanner convertNSData:imageData];
            flutterResult(arr);
        }];
    });
}

- (void)getAssetTypeByIdsWithCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_asyncQueue, ^{
        NSArray *ids = call.arguments;
        NSMutableArray *resultArr = [NSMutableArray new];
        for (NSString *imgId in ids) {
            PHAsset *asset = self.assetDict[imgId];
            if ([asset isImage]) {
                [resultArr addObject:@"1"];
            } else if ([asset isVideo]) {
                [resultArr addObject:@"2"];
            } else {
                [resultArr addObject:@"0"];
            }
        }
        result(resultArr);
    });
}


- (void)getTimeStampWithIdsWithCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSArray<NSString *> *ids = call.arguments;
    NSMutableArray<NSNumber *> *r = [NSMutableArray new];
    for (NSString *assetId in ids) {
        PHAsset *asset = self.assetDict[assetId];
        if (asset) {
            [r addObject:@(asset.creationDate.timeIntervalSince1970 * 1000)];
        } else {
            [r addObject:@0];
        }
    }
    result(r);
}

- (void)isCloudWithCall:(FlutterMethodCall *)call result:(FlutterResult)result {

    NSString *imageId = call.arguments;

    PHAsset *asset = self.assetDict[imageId];
    if (asset) {

    } else {
        result(nil);
    }
}

- (void)getDurationWithId:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *imageId = call.arguments;
    PHAsset *asset = [self.assetDict valueForKey:imageId];
    int duration = (int) [asset duration];
    if (duration == 0) {
        result(nil);
    } else {
        result([[NSNumber alloc] initWithInt:duration]);
    }
}


- (void)getSizeWithId:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *imageId = call.arguments;
    PHAsset *asset = [self.assetDict valueForKey:imageId];
    if (!asset) {
        result([NSDictionary new]);
        return;
    }
    NSUInteger width = [asset pixelWidth];
    NSUInteger height = [asset pixelHeight];
    NSMutableDictionary *dict = [NSMutableDictionary new];
    dict[@"width"] = @(width);
    dict[@"height"] = @(height);
    result(dict);
}

- (void)assetExistsWithId:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *assetId = call.arguments;
    PHFetchResult<PHAsset *> *fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetId] options:[PHFetchOptions new]];
    if (fetchResult != nil && fetchResult.count > 0) {
        result(@YES);
    } else {
        result(@NO);
    }
}

+ (NSArray *)convertNSData:(NSData *)data {
    NSMutableArray *array = [NSMutableArray array];
    char *bytes = (char *)data.bytes;
    for (int i = 0; i < data.length; ++i) {
        [array addObject:@(bytes[i])];
    }
    return array;
}

+ (void)openSetting {
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url];
    }
}

- (void)releaseMemCache:(FlutterMethodCall *)call result:(FlutterResult)result {
    [self.albumCollection removeAllObjects];
    [self.assetDict removeAllObjects];
    [self.albumAssetDict removeAllObjects];
    result(@1);
}


#pragma mark - scan for video

- (void)getVideoPathList:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_asyncQueue, ^{
        BOOL isCache = [call.arguments boolValue];
        if (!isCache) {
            [self refreshGallery];
        }
        
        NSMutableArray * videoAlbumKeys = [NSMutableArray new];
        [self filterAssetWithBlock:^(PHCollection *collection, PHAsset *asset) {
            if ([collection isKindOfClass:PHAssetCollection.class]) {
                if (!asset.isVideo) {
                    return;
                }
                [videoAlbumKeys addObject:collection.localIdentifier];
            }
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            result(videoAlbumKeys);
        });
    });
}

- (void)getAllVideo:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_asyncQueue, ^{
        NSMutableArray<NSString *> *ids = [NSMutableArray new];
        [self filterAssetWithBlock:^(PHCollection *collection, PHAsset *asset) {
            if ([asset isVideo] && ![ids containsObject:asset.localIdentifier]) {
                [ids addObject:asset.localIdentifier];
            }
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            result(ids);
        });
    });
}

- (void)getOnlyVideoWithPathId:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *pathId = call.arguments;
    NSMutableArray *ids = [NSMutableArray new];
    NSArray<PHAsset *> *assetArray = self.albumAssetDict[pathId];

    for (PHAsset *asset in assetArray) {
        if ([asset isVideo]) {
            [ids addObject:asset.localIdentifier];
        }
    }
    result(ids);
}

- (void)getAllLivePhoto:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_asyncQueue, ^{
        NSMutableArray<NSString *> *assetIds = [NSMutableArray new];
        [self filterAssetWithBlock:^(PHCollection *collection, PHAsset *asset) {
            if ([asset isLivePhoto]) {
                NSString *assetId = asset.localIdentifier;
                [assetIds addObject:assetId];
            }
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            result(assetIds);
        });
    });
}

- (void)getAllGif:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_asyncQueue, ^{
        NSMutableArray<NSString *> *assetIds = [NSMutableArray new];
        [self filterAssetWithBlock:^(PHCollection *collection, PHAsset *asset) {
            if ([asset isGif]) {
                NSString *assetId = asset.localIdentifier;
                [assetIds addObject:assetId];
            }
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            result(assetIds);
        });
    });
}

#pragma mark - gif
- (void)videoUrlForGifAsset:(PHAsset*)asset withCompletionBlock:(void (^)(NSString * path))completionBlock {
    PHImageManager *manager = PHImageManager.defaultManager;
    PHImageRequestOptions *options = [PHImageRequestOptions new];
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    [manager requestImageDataForAsset:asset options:options
                        resultHandler:^(NSData *gifData,
                                        NSString *dataUTI,
                                        UIImageOrientation orientation,
                                        NSDictionary *info) {
                            NSString *homePath = NSTemporaryDirectory();
                            NSFileManager *manager = NSFileManager.defaultManager;
                            
                            NSMutableString *path = [NSMutableString stringWithString:homePath];
                            [path appendString:@".gifs"];
                            
                            if (![manager fileExistsAtPath:path]) {
                                [manager createDirectoryAtPath:path withIntermediateDirectories:NO attributes:NULL error:NULL];
                            }
                            
                            [path appendString:@"/"];
                            [path appendString:[MD5Utils getmd5WithString:asset.localIdentifier]];
                            [path appendString:@".gif"];
                            
                            if ([manager fileExistsAtPath:path]) {
                                completionBlock(path);
                            }
                            
                            [manager createFileAtPath:path contents:gifData attributes:@{}];
                            completionBlock(path);
    }];
}
#pragma mark - live photo

- (void)videoUrlForLivePhotoAsset:(PHAsset*)asset withCompletionBlock:(void (^)(NSString * path))completionBlock{
    NSString* filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mov",[NSString stringWithFormat:@"%.0f",[[NSDate date] timeIntervalSince1970]]]];
    NSURL *fileUrl = [NSURL fileURLWithPath:filePath];
    
    PHLivePhotoRequestOptions* options = [PHLivePhotoRequestOptions new];
    options.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
    options.networkAccessAllowed = YES;
    [[PHImageManager defaultManager] requestLivePhotoForAsset:asset targetSize:[UIScreen mainScreen].bounds.size contentMode:PHImageContentModeDefault options:options resultHandler:^(PHLivePhoto * _Nullable livePhoto, NSDictionary * _Nullable info) {
        if(livePhoto){
            NSArray* assetResources = [PHAssetResource assetResourcesForLivePhoto:livePhoto];
            PHAssetResource* videoResource = nil;
            for(PHAssetResource* resource in assetResources){
                if (resource.type == PHAssetResourceTypePairedVideo) {
                    videoResource = resource;
                    break;
                }
            }
            if(videoResource){
                [[PHAssetResourceManager defaultManager] writeDataForAssetResource:videoResource toFile:fileUrl options:nil completionHandler:^(NSError * _Nullable error) {
                    if(!error){
                        completionBlock(filePath);
                    }else{
                        completionBlock(nil);
                    }
                }];
            }else{
                completionBlock(nil);
            }
        }else{
            completionBlock(nil);
        }
    }];
}

#pragma mark - scan for image

- (void)getImagePathList:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_asyncQueue, ^{
        BOOL isCache = [call.arguments boolValue];
        if (!isCache) {
            [self refreshGallery];
        }
        NSMutableArray * imageAlbumKeys = [NSMutableArray new];
        [self filterAssetWithBlock:^(PHCollection *collection, PHAsset *asset) {
            if ([collection isKindOfClass:PHAssetCollection.class]) {
                if (!asset.isImage) {
                    return;
                }
                [imageAlbumKeys addObject:collection.localIdentifier];
            }
        }];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            result(imageAlbumKeys);
        });
    });
}

- (void)getAllImage:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_asyncQueue, ^{
        NSMutableArray<NSString *> *ids = [NSMutableArray new];
        [self filterAssetWithBlock:^(PHCollection *collection, PHAsset *asset) {
            if ([asset isImage] && ![ids containsObject:asset.localIdentifier]) {
                [ids addObject:asset.localIdentifier];
            }
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            result(ids);
        });
    });
}

- (void)getOnlyImageWithPathId:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *pathId = call.arguments;
    NSMutableArray *ids = [NSMutableArray new];
    NSArray<PHAsset *> *assetArray = self.albumAssetDict[pathId];

    for (PHAsset *asset in assetArray) {
        [ids addObject:asset.localIdentifier];
    }
    result(ids);
}

# pragma mark - getAssetWithId

- (void)createAssetWithIdWithCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    dispatch_async(_asyncQueue, ^{
        NSString *localId = call.arguments;
        PHFetchOptions *options = [PHFetchOptions new];
        PHFetchResult<PHAsset *> *fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[localId] options:options];
        if (fetchResult && fetchResult.count != 0) {
            PHAsset *asset = fetchResult[0];
            if (asset) {
                [self handleAsset:asset];
                dispatch_async(dispatch_get_main_queue(), ^{
                    result(asset.localIdentifier);
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    result(nil);
                });
            }
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                result(nil);
            });
        }
    });
}

- (void)handleAsset:(PHAsset *)asset {
    self.assetDict[asset.localIdentifier] = asset;
}

@end
