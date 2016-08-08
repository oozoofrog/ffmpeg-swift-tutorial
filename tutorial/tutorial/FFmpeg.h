//
//  FFmpeg.h
//  tutorial
//
//  Created by jayios on 2016. 8. 8..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef struct Test{
    int values[8];
} Test;

Test* alloc_test();

struct AVDictionary;

BOOL isErr(int err, const char* desc);
void print_err(int err, const char* desc);

@interface FFmpegHelper : NSObject

@end
