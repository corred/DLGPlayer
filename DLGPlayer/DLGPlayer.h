//
//  DLGPlayer.h
//  DLGPlayer
//
//  Created by Liu Junqi on 09/12/2016.
//  Copyright © 2016 Liu Junqi. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DLGPlayerDef.h"

typedef void (^onPauseComplete)(void);

@interface DLGPlayer : NSObject

@property (readonly, strong) UIView *playerView;

@property (nonatomic) double minBufferDuration;
@property (nonatomic) double maxBufferDuration;
@property (nonatomic) double position;
@property (nonatomic) double duration;
@property (nonatomic) BOOL opened;
@property (nonatomic) BOOL playing;
@property (nonatomic) BOOL buffering;
@property (nonatomic) BOOL hasVideo;
@property (nonatomic) BOOL hasAudio;
@property (nonatomic) BOOL hasPicture;

- (void)open:(NSString *)url;
- (void)close;
- (void)play;
- (void)pause;
- (NSDictionary *)findMetadata; //!!!
- (bool)seeking;

@end
