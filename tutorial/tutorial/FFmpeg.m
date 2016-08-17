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

@interface AVFilterHelper ()
{
    AVFilter *buffersrc;
    AVFilter *buffersink;
    AVFilterContext *buffersrc_ctx;
    AVFilterContext *buffersink_ctx;
    AVFilterGraph *filter_graph;
    AVFilterInOut *inputs;
    AVFilterInOut *outputs;
}
@end

@implementation AVFilterHelper

- (nullable instancetype)init {
    self = [super init];
    if (self) {
        buffersrc = avfilter_get_by_name("buffer");
        buffersink = avfilter_get_by_name("buffersink");
        
        filter_graph = avfilter_graph_alloc();
        _filterFrame = av_frame_alloc();
    }
    return self;
}

- (BOOL)setup:(AVFormatContext *)fmt_ctx videoStream:(AVStream *)videoStream filterDescription:(NSString *)filterDescription {
    
    AVRational time_base = videoStream->time_base;
    AVRational pixel_aspect = videoStream->codecpar->sample_aspect_ratio;
    NSString *args = [NSString stringWithFormat:@"video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d", videoStream->codecpar->width, videoStream->codecpar->height, videoStream->codecpar->format, time_base.num, time_base.den, pixel_aspect.num, pixel_aspect.den];
    
    if (isErr(avfilter_graph_create_filter(&buffersrc_ctx, buffersrc, "in", args.UTF8String, nil, filter_graph), "create input filter")) {
        return NO;
    }
    
    if (isErr(avfilter_graph_create_filter(&buffersink_ctx, buffersink, "out", nil, nil, filter_graph), "create output filter")) {
        return NO;
    }
    
    inputs = avfilter_inout_alloc();
    outputs = avfilter_inout_alloc();
    
    outputs->name = av_strdup("in");
    outputs->filter_ctx = buffersrc_ctx;
    outputs->pad_idx = 0;
    outputs->next = nil;
    
    inputs->name = av_strdup("out");
    inputs->filter_ctx = buffersink_ctx;
    inputs->pad_idx = 0;
    inputs->next = nil;
    
    if (isErr(avfilter_graph_parse_ptr(filter_graph, filterDescription.UTF8String, &inputs, &outputs, nil), "graph parse")) {
        [self clearInOut];
        return NO;
    }
    
    if (isErr(avfilter_graph_config(filter_graph, nil), "graph config")) {
        [self clearInOut];
        return NO;
    }
    
    [self clearInOut];
    return YES;
}

- (BOOL)applyFilter:(AVFrame *)sourceFrame {
    if (isErr(av_buffersrc_add_frame_flags(buffersrc_ctx, sourceFrame, AV_BUFFERSRC_FLAG_KEEP_REF), "buffersrc to source frame")) {
        return NO;
    }
    while (1) {
        int ret = av_buffersink_get_frame(buffersink_ctx, _filterFrame);
        if (AVFILTER_EOF(ret)) {
            return YES;
        }
        if (isErr(ret, "buffersink get frame")) {
            return NO;
        }
    }
    return NO;
}

- (void)clearInOut {
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
}

- (void)dealloc {
    av_frame_free(&_filterFrame);
    avfilter_graph_free(&filter_graph);
}

@end
