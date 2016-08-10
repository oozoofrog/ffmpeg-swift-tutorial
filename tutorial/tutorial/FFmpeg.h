//
//  FFmpeg.h
//  tutorial
//
//  Created by jayios on 2016. 8. 8..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <libavfilter/avfilter.h>

typedef struct Test{
    int values[8];
} Test;

Test* alloc_test();

struct AVDictionary;

BOOL isErr(int err, const char* desc);
void print_err(int err, const char* desc);
int opt_set_int_list(AVFilterContext *ctx, const char * key, void *value, int64_t term, int flags);

int AVERROR_CONVERT(int err);

BOOL AVFILTER_EOF(int ret);

@interface FFmpegHelper : NSObject

@end