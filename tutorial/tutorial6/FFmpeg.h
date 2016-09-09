//
//  FFmpeg.h
//  tutorial
//
//  Created by jayios on 2016. 8. 8..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <libavformat/avformat.h>
#import <libavfilter/avfilter.h>
#import <libavfilter/avfiltergraph.h>
#import <libavfilter/buffersrc.h>
#import <libavfilter/buffersink.h>
#import <libswresample/swresample.h>

typedef struct Test{
    int values[8];
} Test;

Test* alloc_test();

struct AVDictionary;

BOOL av_success(int ret);
BOOL av_success_desc(int ret, const char* desc);
BOOL isErr(int err, const char* desc);
void print_err(int err, const char* desc);

int AVERROR_CONVERT(int err);
BOOL IS_AVERROR_EOF(int err);

BOOL AVFILTER_EOF(int ret);

NSString *channels_name(int channels, uint64_t channel_layout);

NSString* codec_name_for_codec_id(enum AVCodecID codec_id);
NSString* codec_name_for_stream(AVStream* stream);
NSString* codec_name_for_codec_parameters(AVCodecParameters *codecpar);
NSString* codec_name_for_codec(AVCodec *codec);
NSString* codec_name_for_codec_ctx(AVCodecContext *ctx);

@interface FFmpegHelper : NSObject

@end

typedef NS_ENUM(NSUInteger, AVFilterApplyResult) {
    AVFilterApplyResultSuccess,
    AVFilterApplyResultContinue,
    AVFilterApplyResultBufferFull,
    AVFilterApplyResultNoMoreFrames,
    AVFilterApplyResultFailed
};
@interface AVFilterHelper : NSObject

- (BOOL)setup:(AVFormatContext *)fmt_ctx videoStream:(AVStream *)videoStream filterDescription:(NSString *)filterDescription;
- (BOOL)setup:(AVFormatContext *)fmt_ctx audioStream:(AVStream *)audioStream abuffer:(NSString *)abuffer_args aformat:(NSString *)aformat_args;

- (AVFilterApplyResult)applyFilter:(AVFrame *)sourceFrame;

@end
