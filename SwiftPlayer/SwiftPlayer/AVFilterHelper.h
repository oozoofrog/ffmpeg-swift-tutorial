//
//  AVFilterHelper.h
//  SwiftPlayer
//
//  Created by Kwanghoon Choi on 2016. 8. 30..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <libavfilter/avfilter.h>
#import <libavfilter/buffersrc.h>
#import <libavfilter/buffersink.h>
#import <libavformat/avformat.h>
#import <libavcodec/avcodec.h>
#import <libavutil/samplefmt.h>

typedef NS_ENUM(NSUInteger, AVFilterHelperType) {
    AVFilterHelperTypeAudio,
    AVFilterHelperTypeVideo,
};

@interface AVFilterHelper : NSObject

@property (nonatomic, readonly) AVFilterHelperType type;

+ (nullable instancetype)audioHelperWithSampleRate:(int)inSampleRate
                                    inSampleFormat:(enum AVSampleFormat)inSampleFmt
                                   inChannelLayout:(int)inChannelLayout
                                        inChannels:(int)channels
                                  outSampleFormats:(enum AVSampleFormat)outSampleFmt
                                    outSampleRates:(int)outSampleRates
                                 outChannelLayouts:(int)outChannelLayouts
                                       outChannels:(int)outChannels
                                          timeBase:(AVRational)time_base
                             context:(nonnull AVCodecContext *)context;

+ (nullable instancetype)videoHelper:(nonnull NSString *)format;

- (BOOL)input:(nullable AVFrame *)frame;

/// return YES - finished, NO - not finished or has error
- (BOOL)output:(nullable AVFrame *)frame;

@end
