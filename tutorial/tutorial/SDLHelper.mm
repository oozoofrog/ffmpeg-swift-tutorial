//
//  SDL.m
//  tutorial
//
//  Created by jayios on 2016. 8. 9..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import "SDLHelper.h"
#import "SDL.h"
#import "SDL_main.h"

BOOL isSDLError(int err) {
    if (0 > err) {
        printf("%s\n", SDL_GetError());
        return YES;
    }
    return NO;
}

void audio_callback(void *userdata, UInt8 *stream, int length) {
    NSLog(@"audio_callback");
}

@implementation SDLHelper

- (instancetype)init {
    self= [super init];
    if (self) {
        /**
         *  directly run initialize function, because of application haven't main.h
         */
        SDL_SetMainReady();
    }
    return self;
}

- (BOOL)SDL_init:(UInt32)flags {
    if (0 > SDL_Init(flags)) {
        NSLog(@"%s", SDL_GetError());
        return NO;
    }
    return YES;
}

+ (SDL_AudioSpec)SDLAudioSpec:(void *)userData codecpar:(AVCodecParameters *)codecpar format:(SDL_AudioFormat)format bufferSize: (size_t)bufferSize {
    SDL_AudioSpec audio_spec;
    
    audio_spec.freq = codecpar->sample_rate;
    audio_spec.channels = codecpar->channels;
    audio_spec.format = format;
    audio_spec.silence = 0;
    audio_spec.samples = bufferSize;
    audio_spec.userdata = userData;
    audio_spec.callback = audio_callback;
    
    return audio_spec;
}

@end
