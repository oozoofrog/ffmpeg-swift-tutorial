//
//  main.m
//  play_audio
//
//  Created by jayios on 2016. 8. 24..
//  Copyright © 2016년 gretech. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioUnit/AudioUnit.h>
#import <AVFoundation/AVFoundation.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        const char *filename = argv[1];
        NSString *path = [[NSString alloc] initWithUTF8String:filename];
        
        dispatch_semaphore_t lock = dispatch_semaphore_create(0);
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            AVAudioEngine *engine = [[AVAudioEngine alloc] init];
            AVAudioPlayerNode *player = [[AVAudioPlayerNode alloc] init];
            [engine attachNode:player];
            
            NSError *err = nil;
            AVAudioFile *file = [[AVAudioFile alloc] initForReading:[NSURL URLWithString:path] error:&err];
            NSLog(@"file -> %@", file);
            if (err) {
                NSLog(@"%@", err);
                dispatch_semaphore_signal(lock);
            }
            
            AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat frameCapacity:file.length];
            
            [file readIntoBuffer:buffer error:&err];
            if (err) {
                NSLog(@"%@", err);
                dispatch_semaphore_signal(lock);
            }
     
            
            [engine connect:player to:[engine outputNode] format:file.processingFormat];
            
            [player scheduleBuffer:buffer atTime:[AVAudioTime timeWithHostTime:mach_absolute_time()] options:AVAudioPlayerNodeBufferInterrupts completionHandler:^{
                dispatch_semaphore_signal(lock);
            }];
            [engine prepare];
            [engine startAndReturnError:&err];
            if (err) {
                NSLog(@"%@", err);
                dispatch_semaphore_signal(lock);
            }
            
            [player play];
            NSLog(@"Play start");
        });
        dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
    }
    return 0;
}
