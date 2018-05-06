//
//  PlayerViewController.h
//
//  Created by Liu Junqi on 06/12/2016.
//  Copyright © 2016 Liu Junqi. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DLGPlayer.h"

typedef enum : NSUInteger {
    DLGPlayerStatusNone,
    DLGPlayerStatusOpening,
    DLGPlayerStatusOpened,
    DLGPlayerStatusPlaying,
    DLGPlayerStatusBuffering,
    DLGPlayerStatusPaused,
    DLGPlayerStatusEOF,
    DLGPlayerStatusClosing,
    DLGPlayerStatusClosed,
} DLGPlayerStatus;

@interface PlayerViewController : UIViewController

- (IBAction)closeButtonAction:(id)sender;
@property (weak, nonatomic) IBOutlet UIView *topBarView;
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UIView *actionsMenuView;
@property (weak, nonatomic) IBOutlet UIView *videoBoxView;
@property (weak, nonatomic) IBOutlet UIView *albumCoverView;
@property (weak, nonatomic) IBOutlet UIView *playerControlView;
@property (weak, nonatomic) IBOutlet UIView *bottomBarView;
@property (weak, nonatomic) IBOutlet UILabel *timePassedLabel;
@property (weak, nonatomic) IBOutlet UILabel *timeRemainLabel;
@property (weak, nonatomic) IBOutlet UIButton *playPauseButton;
@property (weak, nonatomic) IBOutlet UISlider *positionSllder;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *loadingActivity;

- (IBAction)playPauseButtonAction:(id)sender;
- (IBAction)prevTrackButtonAction:(id)sender;
- (IBAction)nextTrackButtonAction:(id)sender;
- (IBAction)positionStartSlideAction:(id)sender;
- (IBAction)positionChangedAction:(id)sender;
- (IBAction)positionEndSlideAction:(id)sender;

@property (nonatomic, copy) NSString *url;
@property (nonatomic) double position;
@property (nonatomic) BOOL autoplay;
@property (nonatomic) BOOL repeat;
@property (nonatomic) BOOL preventFromScreenLock;
@property (nonatomic, readonly) DLGPlayerStatus status;

- (void)open;
- (void)close;
- (void)play;
- (void)pause;

@end
