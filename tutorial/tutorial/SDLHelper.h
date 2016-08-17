//
//  SDL.h
//  tutorial
//
//  Created by jayios on 2016. 8. 9..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SDL_audio.h"
#import <libavcodec/avcodec.h>

BOOL isSDLError(int err);

@interface SDLHelper : NSObject

- (BOOL)SDL_init:(UInt32)flags;
+ (SDL_AudioSpec)SDLAudioSpec:(void *)userData codecpar:(AVCodecParameters *)codecpar format:(SDL_AudioFormat)format bufferSize: (size_t)bufferSize;

@end
