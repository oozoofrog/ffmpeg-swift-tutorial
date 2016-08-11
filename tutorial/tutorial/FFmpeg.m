//
//  FFmpeg.m
//  tutorial
//
//  Created by jayios on 2016. 8. 8..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import "FFmpeg.h"
#import <libavformat/avformat.h>
#import <libavcodec/avcodec.h>
#import <libavutil/error.h>
#import <libavutil/opt.h>

struct AVDictionary {
    int count;
    AVDictionaryEntry *elems;
};

Test* alloc_test() {
    Test* test = malloc(sizeof(Test));
    for (int i=0; i<8; i++) {
        test->values[i] = (i + 1) * 10;
    }
    return test;
}

BOOL isErr(int err, const char* desc) {
    if (err >= 0) {
        return NO;
    }
    print_err(err, desc);
    return YES;
}

void print_err(int err, const char *desc) {
    if (NULL == desc) {
        printf("😱 LIBAV ERR -> %s", av_err2str(err));
    }
    else {
        printf("😱 LIBAV ERR(%s) -> %s", desc, av_err2str(err));
    }
}

int AVERROR_CONVERT(int err) {
    return AVERROR(err);
}

BOOL AVFILTER_EOF(int ret) {
    return ret == AVERROR(EAGAIN) || ret == AVERROR_EOF;
}

@implementation FFmpegHelper

@end
