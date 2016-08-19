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

typedef struct Test{
    int values[8];
} Test;

Test* alloc_test();

struct AVDictionary;

BOOL isErr(int err, const char* desc);
void print_err(int err, const char* desc);

int AVERROR_CONVERT(int err);
BOOL IS_AVERROR_EOF(int err);

BOOL AVFILTER_EOF(int ret);

@interface FFmpegHelper : NSObject

@end

@interface AVFilterHelper : NSObject

@property (nonatomic, assign) AVFrame *filterFrame;

- (BOOL)setup:(AVFormatContext *)fmt_ctx videoStream:(AVStream *)videoStream filterDescription:(NSString *)filterDescription;

- (BOOL)applyFilter:(AVFrame *)sourceFrame;

@end
