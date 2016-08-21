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
BOOL sdl_success(int ret);

@interface SDLHelper : NSObject

- (BOOL)SDL_init:(UInt32)flags;

@end
