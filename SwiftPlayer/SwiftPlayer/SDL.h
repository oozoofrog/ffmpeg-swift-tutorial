//
//  SDL.h
//  SwiftPlayer
//
//  Created by Kwanghoon Choi on 2016. 8. 29..
//  Copyright © 2016년 Kwanghoon Choi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SDL.h>
#import <SDL_main.h>

#undef main

@interface SDL : NSObject

+ (BOOL)ready;

@end
