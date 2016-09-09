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

BOOL av_success(int ret) {
    if (0 <= ret) {
        return YES;
    }
    printf("🤔 %s\n", av_err2str(ret));
    return NO;
}

BOOL av_success_desc(int ret, const char* desc) {
    if (0 <= ret) {
        return YES;
    }
    printf("🤔 %s, %s\n", av_err2str(ret), desc);
    return NO;
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
        printf("😱 LIBAV ERR -> %s(%d)\n", av_err2str(err), err);
    }
    else {
        printf("😱 LIBAV ERR(%s) -> %s(%d)\n", desc, av_err2str(err), err);
    }
}

int AVERROR_CONVERT(int err) {
    return AVERROR(err);
}

BOOL IS_AVERROR_EOF(int err) {
    return err == AVERROR_EOF;
}

BOOL AVFILTER_EOF(int ret) {
    return ret == AVERROR(EAGAIN) || ret == AVERROR_EOF;
}

NSString *channels_name(int channels, uint64_t channel_layout) {
    char buf[128];
    av_get_channel_layout_string(buf, 128, channels, channel_layout);
    return [[NSString alloc] initWithCString:buf encoding:NSASCIIStringEncoding];
}

NSString* codec_name_for_codec_id(enum AVCodecID codec_id) {
    return [NSString stringWithCString:avcodec_get_name(codec_id) encoding:NSASCIIStringEncoding];
}
NSString* codec_name_for_stream(AVStream* stream) {
    return codec_name_for_codec_id(stream->codecpar->codec_id);
}
NSString* codec_name_for_codec_parameters(AVCodecParameters *codecpar) {
    return codec_name_for_codec_id(codecpar->codec_id);
}

NSString* codec_name_for_codec(AVCodec *codec) {
    return codec_name_for_codec_id(codec->id);
}
NSString* codec_name_for_codec_ctx(AVCodecContext *ctx) {
    return codec_name_for_codec_id(ctx->codec_id);
}

@implementation FFmpegHelper

@end

@interface AVFilterHelper ()
{
    BOOL isAudio;
    
    AVFilter *buffersrc;
    AVFilter *buffersink;
    AVFilterContext *buffersrc_ctx;
    AVFilterContext *buffersink_ctx;
    AVFilterGraph *filter_graph;
    AVFilterInOut *inputs;
    AVFilterInOut *outputs;
    
    AVFilter *abuffer;
    AVFilterContext *abuffer_ctx;
    AVFilter *abuffersink;
    AVFilterContext *abuffersink_ctx;
    AVFilter *aformat;
    AVFilterContext *aformat_ctx;
}
@end

@implementation AVFilterHelper

- (nullable instancetype)init {
    self = [super init];
    if (self) {
        avfilter_register_all();
        
        filter_graph = avfilter_graph_alloc();
    }
    return self;
}

- (void)dealloc
{
    avfilter_graph_free(&filter_graph);
}

- (BOOL)setup:(AVFormatContext *)fmt_ctx videoStream:(AVStream *)videoStream filterDescription:(NSString *)filterDescription {
    isAudio = false;
    buffersrc = avfilter_get_by_name("buffer");
    buffersink = avfilter_get_by_name("buffersink");
    
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

- (BOOL)setup:(AVFormatContext *)fmt_ctx audioStream:(AVStream *)audioStream abuffer:(NSString *)abuffer_args aformat:(NSString *)aformat_args {
    
    NSLog(@"%s -> abuffer: %@, aformat: %@", __PRETTY_FUNCTION__, abuffer_args, aformat_args);
    isAudio = true;
    
    abuffer = avfilter_get_by_name("abuffer");
    abuffersink = avfilter_get_by_name("abuffersink");
    aformat = avfilter_get_by_name("aformat");
    
    if (isErr(avfilter_graph_create_filter(&abuffer_ctx, abuffer, "abuffer", abuffer_args.UTF8String, nil, filter_graph), "audio buffer")) {
        return NO;
    }
    
    if (isErr(avfilter_graph_create_filter(&aformat_ctx, aformat, "aformat converter", aformat_args.UTF8String, nil, filter_graph), "audio format")) {
        return NO;
    }
    
    if (isErr(avfilter_graph_create_filter(&abuffersink_ctx, abuffersink, "abuffersink", NULL, NULL, filter_graph), "abuffersink")) {
        return NO;
    }
    
    if (isErr(avfilter_link(abuffer_ctx, 0, aformat_ctx, 0), "link to aformat from abuffer")) {
        return NO;
    }
    if (isErr(avfilter_link(aformat_ctx, 0, abuffersink_ctx, 0), "link to abuffersink from aformat")) {
        return NO;
    }
    
    if (isErr(avfilter_graph_config(filter_graph, nil), "config audio filter")) {
        return NO;
    }
    
    return YES;
}

- (AVFilterApplyResult)applyFilter:(AVFrame *)sourceFrame {
    AVFilterContext *src;
    AVFilterContext *sink;
    if (isAudio) {
        src = abuffer_ctx;
        sink = abuffersink_ctx;
    }
    else {
        src = buffersrc_ctx;
        sink = buffersink_ctx;
    }
    
    int ret = av_buffersrc_add_frame_flags(src, sourceFrame, AV_BUFFERSRC_FLAG_KEEP_REF);
    if (0 > ret) {
        return AVFilterApplyResultFailed;
    }
    ret = av_buffersink_get_frame(sink, sourceFrame);
    if (0 <= ret) {
        return AVFilterApplyResultSuccess;
    }
    else if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
        return AVFilterApplyResultNoMoreFrames;
    }
    else if (0 > ret) {
        return AVFilterApplyResultFailed;
    }
    
    return AVFilterApplyResultContinue;
}

- (void)clearInOut {
    avfilter_inout_free(&inputs);
    avfilter_inout_free(&outputs);
}

@end
