//
//  AVFilterHelper.m
//  SwiftPlayer
//
//  Created by Kwanghoon Choi on 2016. 8. 30..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

#import "AVFilterHelper.h"

@interface AVFilterHelper ()
{
    AVFilterGraph *audio_graph;
    AVFilterContext *abuffer_ctx;
    AVFilterContext *abuffersink_ctx;
    AVFilterContext *aformat_ctx;
}

@property (nonatomic, strong) NSString *audioInputArgs;
@property (nonatomic, strong) NSString *audioFormatArgs;
@property (nonatomic, assign) AVFilterHelperType type;

@end

@implementation AVFilterHelper

+ (instancetype)audioHelperWithSampleRate:(int)inSampleRate
                           inSampleFormat:(enum AVSampleFormat)inSampleFmt
                          inChannelLayout:(int)inChannelLayout
                               inChannels:(int)channels
                         outSampleFormats:(enum AVSampleFormat)outSampleFmt
                           outSampleRates:(int)outSampleRates
                        outChannelLayouts:(int)outChannelLayouts
                                 timeBase:(AVRational)time_base
                                  context:(AVCodecContext *)context{
    AVFilterHelper *helper = [[AVFilterHelper alloc] initWithType:AVFilterHelperTypeAudio];
    if ([helper setupAudioWithSampleRate:inSampleRate
                          inSampleFormat:inSampleFmt
                         inChannelLayout:inChannelLayout
                              inChannels:channels
                        outSampleFormats:outSampleFmt
                          outSampleRates:outSampleRates
                       outChannelLayouts:outChannelLayouts
                                timeBase:time_base
                                 context:context]) {
        return helper;
    }
    return nil;
}

+ (instancetype)videoHelper:(NSString *)format {
    return nil;
}

- (instancetype)initWithType:(AVFilterHelperType)type {
    self = [super init];
    if (self) {
        self.type = type;
    }
    return self;
}

- (BOOL)setupAudioWithSampleRate:(int)inSampleRate
                  inSampleFormat:(enum AVSampleFormat)inSampleFmt
                 inChannelLayout:(int)inChannelLayout
                      inChannels:(int)channels
                outSampleFormats:(enum AVSampleFormat)outSampleFmt
                  outSampleRates:(int)outSampleRates
               outChannelLayouts:(int)outChannelLayouts
                        timeBase:(AVRational)time_base
                         context:(AVCodecContext *)context {
    
    audio_graph = avfilter_graph_alloc();
    if (nil == audio_graph) {
        NSLog(@"Couldn't allocate filter graph");
        return NO;
    }
    
    AVFilter *abuffer = avfilter_get_by_name("abuffer");
    AVFilter *aformat = avfilter_get_by_name("aformat");
    AVFilter *abuffer_sink = avfilter_get_by_name("abuffersink");
    
    NSString *buffer_arg = [[NSString alloc] initWithFormat:@"sample_rate=%d:sample_fmt=%s:channels=%d:time_base=%d/%d:channel_layout=0x%x", inSampleRate, av_get_sample_fmt_name(inSampleFmt), channels, time_base.num, time_base.den, inChannelLayout];
    int ret = avfilter_graph_create_filter(&abuffer_ctx, abuffer, "abuffer_context", buffer_arg.UTF8String, NULL, audio_graph);
    if (0 > ret) {
        printf("%s:%d - %s", __PRETTY_FUNCTION__, __LINE__, av_err2str(ret));
        return NO;
    }
    
    NSString *format_arg = [[NSString alloc] initWithFormat:@"sample_rates=%d:sample_fmts=%s:channel_layouts=%x", outSampleRates, av_get_sample_fmt_name(outSampleFmt), outChannelLayouts];
    ret = avfilter_graph_create_filter(&aformat_ctx, aformat, "aformat_context", format_arg.UTF8String, nil, audio_graph);
    if (0 > ret) {
        printf("%s:%d - %s", __PRETTY_FUNCTION__, __LINE__, av_err2str(ret));
        return NO;
    }
    
    ret = avfilter_graph_create_filter(&abuffersink_ctx, abuffer_sink, "abuffersink_context", nil, nil, audio_graph);
    if (0 > ret) {
        printf("%s:%d - %s", __PRETTY_FUNCTION__, __LINE__, av_err2str(ret));
        return NO;
    }
    
    ret = avfilter_link(abuffer_ctx, 0, aformat_ctx, 0);
    if (0 > ret) {
        printf("%s:%d - %s", __PRETTY_FUNCTION__, __LINE__, av_err2str(ret));
        return NO;
    }
    ret = avfilter_link(aformat_ctx, 0, abuffersink_ctx, 0);
    if (0 > ret) {
        printf("%s:%d - %s", __PRETTY_FUNCTION__, __LINE__, av_err2str(ret));
        return NO;
    }
    
    ret = avfilter_graph_config(audio_graph, nil);
    if (0 > ret) {
        printf("%s:%d - %s", __PRETTY_FUNCTION__, __LINE__, av_err2str(ret));
        return NO;
    }
    
    return YES;
}

- (BOOL)input:(AVFrame *)frame {
    
    int ret = av_buffersrc_write_frame(abuffer_ctx, frame);
    if (0 > ret) {
        printf("%s:%d - %s", __PRETTY_FUNCTION__, __LINE__, av_err2str(ret));
        return NO;
    }
    
    return YES;
}

- (BOOL)output:(AVFrame *)frame {
    int ret = av_buffersink_get_frame(abuffersink_ctx, frame);
    
    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
        return YES;
    }
    if ( 0 > ret) {
        printf("%s:%d - %s", __PRETTY_FUNCTION__, __LINE__, av_err2str(ret));
        return YES;
    }
    return NO;
}

@end
