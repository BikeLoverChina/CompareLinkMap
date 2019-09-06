//
//  LinkMapHandler.m
//  CompareLinkMap
//
//  Created by 周末 on 2018/5/12.
//  Copyright © 2018年 周末. All rights reserved.
//

#import "LinkMapHandler.h"


@implementation LinkMapHandler

+ (void)linkMapPathForChoose:(void (^)(NSString *linkMapPath))block{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.resolvesAliases = NO;
    panel.canChooseFiles = YES;
    
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            NSURL *document = [[panel URLs] objectAtIndex:0];
            block(document.path);
        }
    }];
}

+ (void)linkMapResultPathForChoose:(void (^)(NSString *resultPath))block{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = YES;
    panel.resolvesAliases = NO;
    panel.canChooseFiles = NO;
    
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            NSURL *document = [[panel URLs] objectAtIndex:0];

            NSDate *date = [NSDate dateWithTimeIntervalSinceNow:0];
            NSCalendar *calendar = [NSCalendar currentCalendar];
            NSDateComponents *components = [calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:date];
            
            NSString *path = @"linkMap_";
            path = [path stringByAppendingFormat:@"%ld%ld%ld.txt",(long)components.year,(long)components.month,(long)components.day];
            path = [document.path stringByAppendingPathComponent:path];
            block(path);
        }
    }];
}

/**
 检验文件是否是LinkMap文件
 */
+ (BOOL)checkLinkMapContent:(NSString *)content{
    NSArray *checkStrings = @[@"# Path:",@"# Object files:",@"# Symbols:"];
    for(NSString *checkString in checkStrings){
        NSRange objectFilesRange = [content rangeOfString:checkString];
        if(objectFilesRange.location == NSNotFound){
            return NO;
        }
    }
    return YES;
}

+ (NSDictionary *)symbolMapFromContent:(NSString *)content keyWord:(NSString *)keyWord sortKeyWord:(NSString *)sortKey {
    __block NSMutableDictionary <NSString *, SymbolModel *>*symbolMap = [NSMutableDictionary new];
    
    NSArray *objectFilesSeparated = [content componentsSeparatedByString:@"# Object files:"];
    NSArray *sectionsSeparated = [[objectFilesSeparated lastObject] componentsSeparatedByString:@"# Sections:"];
    NSString *objectFilesContent = [sectionsSeparated firstObject];
    NSString *sizeCountContent = [sectionsSeparated lastObject];
    NSArray <NSString *> *objectFilesLines = [objectFilesContent componentsSeparatedByString:@"\n"];
    NSArray <NSString *> *sizeLines = [sizeCountContent componentsSeparatedByString:@"\n"];
    
    [objectFilesLines enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSRange leftRange = [obj rangeOfString:@"["];
        NSRange rightRange = [obj rangeOfString:@"]"];
        if(leftRange.location != NSNotFound && rightRange.location != NSNotFound){
            NSString *fileKey = [obj substringToIndex:rightRange.location +1];
            NSString *fileName = [obj substringFromIndex:rightRange.location +1];
            fileName = [[fileName componentsSeparatedByString:@"/"] lastObject];
            if([keyWord isEqualToString:@""] || [fileName containsString:keyWord]){
                SymbolModel *model = [SymbolModel new];
                model.fileName = fileName;
                symbolMap[fileKey] = model;
            }
        }
    }];
    BOOL isMethod = [sortKey isEqualToString:@"singleClass"];
    __block NSMutableDictionary *map = [NSMutableDictionary new];
    [sizeLines enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSRange leftRange = [obj rangeOfString:@"["];
        NSRange rightRange = [obj rangeOfString:@"]"];
        if(leftRange.location != NSNotFound && rightRange.location != NSNotFound){
            NSArray <NSString *>*sizeArray = [obj componentsSeparatedByString:@"\t"];
            if(sizeArray.count == 3){
                NSString *lastString = sizeArray.lastObject;
                rightRange = [lastString rangeOfString:@"]"];
                NSString *fileKey = [sizeArray.lastObject substringToIndex:rightRange.location+1];
                SymbolModel *model = symbolMap[fileKey];
                if(model){
                    NSUInteger size = strtoul([sizeArray[1] UTF8String], nil, 16);
                    float kb = size/1024.00;
                    model.linkMapSize +=kb;
                    if ([[lastString substringFromIndex:(lastString.length-1)] isEqualToString:@"]"]) {
                        if (!isMethod) {
                            map[model.fileName] = @(model.linkMapSize);
                        } else {
                            NSRange methodRange = NSMakeRange(0, 0);
                            if ([lastString containsString:@"+["]) {
                                methodRange = [sizeArray.lastObject rangeOfString:@"+["];
                            } else if ([lastString containsString:@"-["]) {
                                methodRange = [sizeArray.lastObject rangeOfString:@"-["];
                            }
                            if (methodRange.location != 0 && methodRange.length != 0) {
                                NSString *method = [sizeArray.lastObject substringFromIndex:methodRange.location];
                                map[method] = @(kb);
                            }
                        }
                    }
                }
            }
        }
    }];
    return [map copy];
}

+ (NSString *)compareLinkMapContent1:(NSString *)content1 keyWord:(NSString *)keyWord sortKeyWord:(NSString *)sortKey{
    BOOL method = [sortKey isEqualToString:@"singleClass"];
    NSMutableString *result = [NSMutableString new];
     result =[@"    大小\t\t名称\r\n\r\n" mutableCopy];
    NSDictionary *result1 = [LinkMapHandler symbolMapFromContent:content1 keyWord:keyWord sortKeyWord:sortKey];
    if (!method) {
        __block NSMutableArray *addModels = [NSMutableArray new];
        [result1 enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            SymbolModel *model = [SymbolModel new];
            model.fileName = key;
            model.linkMapSize = [obj floatValue];
            [addModels addObject:model];
        }];
        
        addModels = [LinkMapHandler descend:addModels sortKeyWord:sortKey];
        [result appendString:[LinkMapHandler contentForModels:addModels].copy];
    } else {
        result =[@"方法大小\t\t名称\r\n\r\n" mutableCopy];
        
        __block NSMutableArray *addModels = [NSMutableArray new];
        [result1 enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            SymbolModel *model = [SymbolModel new];
            model.methodName = key;
            model.methodSize = [obj floatValue];
            [addModels addObject:model];
        }];
        addModels = [LinkMapHandler descendMethod:addModels];
        [result appendString:[LinkMapHandler contentForModelsMethod:addModels].copy];
    }
    return result;
}

// 降序排序
+ (NSMutableArray <SymbolModel *>*)descend:(NSMutableArray <SymbolModel *>*)array sortKeyWord:(NSString *)sortKey{
    NSArray <SymbolModel *>*newArray = [array sortedArrayUsingComparator:^NSComparisonResult(SymbolModel *obj1, SymbolModel *obj2) {
        float value1 = obj1.linkMapSize;
        float value2 = obj2.linkMapSize;
        if( value1> value2){
            return NSOrderedAscending;
        }
        else{
            return NSOrderedDescending;
        }
    }];
    return [newArray mutableCopy];
}

+ (NSMutableArray <SymbolModel *>*)descendMethod:(NSMutableArray <SymbolModel *>*)array {
    NSArray <SymbolModel *>*newArray = [array sortedArrayUsingComparator:^NSComparisonResult(SymbolModel *obj1, SymbolModel *obj2) {
        float value1 = obj1.methodSize;
        float value2 = obj2.methodSize;
        if( value1> value2){
            return NSOrderedAscending;
        }
        else{
            return NSOrderedDescending;
        }
    }];
    return [newArray mutableCopy];
}

+ (NSMutableString *)contentForModels:(NSArray <SymbolModel *>*)models{
    NSMutableString *content = [NSMutableString new];
    __block float compareCount = 0;
    [models enumerateObjectsUsingBlock:^(SymbolModel * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        compareCount += obj.linkMapSize;
       [content appendFormat:@"   %0.2fK\t\t%@\r\n",obj.linkMapSize,obj.fileName];
    }];
    
    if(compareCount != 0){
        [content appendString:@"\r\n"];
        [content appendString:@"总计：\r\n"];
        [content appendFormat:@"%0.2fM\r\n",compareCount/1024.00];
        [content appendString:@"\r\n\r\n"];
    }
    return content;
}

+ (NSMutableString *)contentForModelsMethod:(NSArray <SymbolModel *>*)models{
    NSMutableString *content = [NSMutableString new];
    __block CGFloat total = 0;
    [models enumerateObjectsUsingBlock:^(SymbolModel * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [content appendFormat:@"   %0.2fK\t\t%@\r\n",obj.methodSize,obj.methodName];
        total += obj.methodSize;
    }];
    [content appendString:@"\r\n"];
    [content appendFormat:@"总计：   %0.2fK\t\t",total];
    return content;
}

@end
