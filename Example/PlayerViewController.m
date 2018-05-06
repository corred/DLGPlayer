//
//  PlayerViewController.m
//
//  Created by Liu Junqi on 06/12/2016.
//  Copyright © 2016 Liu Junqi. All rights reserved.
//  Modifited by Corred on 06/12/2016.

#import "PlayerViewController.h"
#import "DLGPlayerUtils.h"
#import "AppDelegate.h"
#import "PlayerRootViewController.h"
#import "PlaylistViewController.h"
@import MediaPlayer;
@import AVFoundation;


typedef enum : NSUInteger {
    DLGPlayerOperationNone,
    DLGPlayerOperationOpen,
    DLGPlayerOperationPlay,
    DLGPlayerOperationPause,
    DLGPlayerOperationClose,
} DLGPlayerOperation;

@interface PlayerViewController ()
{
    BOOL animatingHUD;
    NSTimeInterval showHUDTime;
    NSMutableDictionary* nowPlayingInfo;
}

@property (nonatomic, strong) DLGPlayer *player;
@property (nonatomic) UITapGestureRecognizer *grTap;
@property (nonatomic) dispatch_source_t timer;
@property (nonatomic) BOOL updateHUD;
@property (nonatomic) NSTimer *timerForHUD;
@property (nonatomic, readwrite) DLGPlayerStatus status;
@property (nonatomic) DLGPlayerOperation nextOperation;

@end

@implementation PlayerViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.autoplay = YES;
    
    [self initPlayer];
    [self initTapGesutre];
    self.status = DLGPlayerStatusNone;
    self.nextOperation = DLGPlayerOperationNone;
    
    nowPlayingInfo = [NSMutableDictionary dictionary];
    [self commandCenterInit];
    
    [self actionsMenuButtonsOrder];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self registerNotification];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self unregisterNotification];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self changeOrientation:[UIApplication sharedApplication].statusBarOrientation];
    
   // [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
  //  [self becomeFirstResponder];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration
{
    [self changeOrientation:orientation];
}

- (void)changeOrientation:(UIInterfaceOrientation)orientation
{
    if (UIInterfaceOrientationIsPortrait(orientation)) {
        
        self.actionsMenuView.hidden = NO;
        [UIView animateWithDuration:0.5f animations:^{
            self.actionsMenuView.alpha = 1.0f;
        }];
        
        [self showHUD];
        [self stopTimerForHideHUD];
    }
    else {
        self.actionsMenuView.hidden = YES;
        self.actionsMenuView.alpha = 0.0f;
        [self showHUD];
    }
}

- (void)actionsMenuButtonsOrder
{
    int const buttonWidth = 44;
    
    double l = (self.actionsMenuView.frame.size.width-buttonWidth*self.actionsMenuView.subviews.count)/(self.actionsMenuView.subviews.count+1);
    double s = l;
    
    UIButton *button;
    for (button in self.actionsMenuView.subviews) {
        CGRect frame = button.frame;
        frame.origin.x = s;
        button.frame = frame;
        
        s = s+l+buttonWidth;
    }
}

- (PlaylistViewController *)getPlaylistViewController
{
    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    PlayerRootViewController *playerRootViewController = (PlayerRootViewController *)appDelegate.testViewController;
    return (PlaylistViewController *)playerRootViewController.rightViewController;
}

- (void)registerNotification
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(notifyAppWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [nc addObserver:self selector:@selector(audioSessionWasInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    [nc addObserver:self selector:@selector(notifyPlayerOpened:) name:DLGPlayerNotificationOpened object:self.player];
    [nc addObserver:self selector:@selector(notifyPlayerClosed:) name:DLGPlayerNotificationClosed object:self.player];
    [nc addObserver:self selector:@selector(notifyPlayerEOF:) name:DLGPlayerNotificationEOF object:self.player];
    [nc addObserver:self selector:@selector(notifyPlayerBufferStateChanged:) name:DLGPlayerNotificationBufferStateChanged object:self.player];
    [nc addObserver:self selector:@selector(notifyPlayerError:) name:DLGPlayerNotificationError object:self.player];
}

- (void)unregisterNotification
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self];
}

- (IBAction)closeButtonAction:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - remote control events

- (void)commandCenterInit
{
//    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
//    [self becomeFirstResponder];
    

    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
 
    // toggle play/pause the current track.
    [commandCenter.togglePlayPauseCommand setEnabled:YES];
    [commandCenter.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        if (self.player.playing) {
            [self pause];
        }
        else {
            [self play];
        }
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    // play the current track.
    [commandCenter.playCommand setEnabled:YES];
    [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        [self play];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    // pause the current track.
    [commandCenter.pauseCommand setEnabled:YES];
    [commandCenter.pauseCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        [nowPlayingInfo setObject:[NSNumber numberWithFloat:ceil(self.player.position)] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime]; //currentTrackTime:
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
        [self pause];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    // forward to next track
    [commandCenter.nextTrackCommand setEnabled:YES];
    [commandCenter.nextTrackCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        [self nextTrack];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    // back to previous track
    [commandCenter.previousTrackCommand setEnabled:YES];
    [commandCenter.previousTrackCommand addTargetWithHandler: ^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        [self previousTrack];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    //seek
    [commandCenter.changePlaybackPositionCommand setEnabled:YES];
    [commandCenter.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        MPChangePlaybackPositionCommandEvent* seekEvent = (MPChangePlaybackPositionCommandEvent*)event;
        NSTimeInterval posTime = seekEvent.positionTime;
        self.position = posTime;
        return MPRemoteCommandHandlerStatusSuccess;
    }];

}

- (void)audioSessionWasInterrupted:(NSNotification *)notification
{
    AVAudioSessionInterruptionType type = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        [self pause];
        //[self.playPauseButton setImage:[UIImage imageNamed:@"play_button"] forState:UIControlStateNormal];
    }
}

//- (BOOL) canBecomeFirstResponder
//{
//    return YES;
//}
//
//- (void)remoteControlReceivedWithEvent:(UIEvent *)event
//{
//    NSLog(@"received event!");
//}

#pragma mark - play, pause, previous, next button action

- (IBAction)playPauseButtonAction:(id)sender
{
    if (self.player.playing) {
        [self pause];
    }
    else {
        [self play];
    }
}

- (IBAction)prevTrackButtonAction:(id)sender
{
    [self previousTrack];
}

- (IBAction)nextTrackButtonAction:(id)sender
{
    [self nextTrack];
}

#pragma mark - Slider

- (IBAction)positionStartSlideAction:(id)sender
{
    if (UIDeviceOrientationIsLandscape([[UIDevice currentDevice] orientation])) {
        [self stopTimerForHideHUD];
    }
    
    self.updateHUD = NO;
    self.grTap.enabled = NO;
}

- (IBAction)positionChangedAction:(id)sender
{
    UISlider *slider = sender;
    int position = slider.value;
    self.timePassedLabel.text = [DLGPlayerUtils durationStringFromSeconds:position];
    
    int duration = slider.maximumValue;
    int timeRemainSeconds = duration-position;
    self.timeRemainLabel.text = [NSString stringWithFormat:@"-%@", [DLGPlayerUtils durationStringFromSeconds:timeRemainSeconds]];
}

- (IBAction)positionEndSlideAction:(id)sender
{
    UISlider *slider = sender;
    float position = slider.value;
    self.position = position;
    self.updateHUD = YES;
    self.grTap.enabled = YES;
    
    if (UIDeviceOrientationIsLandscape([[UIDevice currentDevice] orientation])) {
        [self showHUD];
    }
}



#pragma mark - syncHUD

- (void)syncHUD
{
    [self syncHUD:NO];
}

- (void)syncHUD:(BOOL)force
{
    if (!force) {
        if (self.topBarView.hidden) return;
        if (!self.player.playing) return;
        if (!self.updateHUD) return;
    }
    
    if (self.status == DLGPlayerStatusNone || self.status == DLGPlayerStatusClosed || self.player.seeking) {
        return;
    }
    
    //position
    int position = ceil(self.player.position);
    self.timePassedLabel.text = [DLGPlayerUtils durationStringFromSeconds:position];
    self.positionSllder.value = position; //slider
    
    //duration
    int duration = ceil(self.player.duration);
    if (duration <= 0) {
        [self updateTitle]; //live update title
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
    }
    else {
        int timeRemainSeconds = duration-position;
        NSString *timeRemain = @"-";
        self.timeRemainLabel.text = [timeRemain stringByAppendingString:[DLGPlayerUtils durationStringFromSeconds:timeRemainSeconds]];
    }
}

- (void)updateTitle
{
    NSDictionary *metadata = [self.player findMetadata];
    if (!metadata) {
        self.titleLabel.text = [self.url lastPathComponent];
        return;
    }
    
    NSString *title = nil;
    
    //from online-radio
    NSString *streamTitle = metadata[@"streamtitle"];
    if (!streamTitle) {
        //from file tags
        NSString *t = metadata[@"title"];
        NSString *a = metadata[@"artist"];
        
        if (t) {
            title = t;
            [nowPlayingInfo setObject:t forKey:MPMediaItemPropertyTitle]; //Title
        }
        if (a) {
            title = [NSString stringWithFormat:@"%@ - %@", a, t];
            [nowPlayingInfo setObject:a forKey:MPMediaItemPropertyArtist]; //Artist
        }
    }
    else {
        title = streamTitle;
        [nowPlayingInfo setObject:streamTitle forKey:MPMediaItemPropertyTitle]; //Title
    }

    //default
    if (!title) {
        title = [self.url lastPathComponent];
        [nowPlayingInfo setObject:title forKey:MPMediaItemPropertyTitle]; //Title
    }
    
    //show on label
    self.titleLabel.text = title;
}

#pragma mark - player control actions

- (void)open
{
    if (self.status == DLGPlayerStatusClosing) {
        self.nextOperation = DLGPlayerOperationOpen;
        return;
    }
    if (self.status != DLGPlayerStatusNone &&
        self.status != DLGPlayerStatusClosed) {
        return;
    }
    self.status = DLGPlayerStatusOpening;
    [self.loadingActivity startAnimating];
    [self.player open:self.url];
}

- (void)close
{
//    if (self.status == DLGPlayerStatusOpening) {
//        self.nextOperation = DLGPlayerOperationClose;
//        return;
//    }
    
    if (self.status == DLGPlayerStatusClosing) {
        return;
    }
    self.status = DLGPlayerStatusClosing;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [self.player close];
}

- (void)play
{
    if (self.status == DLGPlayerStatusNone ||
        self.status == DLGPlayerStatusClosed) {
        [self open];
        self.nextOperation = DLGPlayerOperationPlay;
    }
    if (self.status != DLGPlayerStatusOpened &&
        self.status != DLGPlayerStatusPaused &&
        self.status != DLGPlayerStatusEOF) {
        return;
    }
    self.status = DLGPlayerStatusPlaying;
    [UIApplication sharedApplication].idleTimerDisabled = self.preventFromScreenLock;
    [self.player play];
    [self.playPauseButton setImage:[UIImage imageNamed:@"pause_button"] forState:UIControlStateNormal];
}

- (void)replay
{
    self.player.position = 0;
    [self play];
}

- (void)pause
{
    if (self.status != DLGPlayerStatusOpened &&  self.status != DLGPlayerStatusPlaying && self.status != DLGPlayerStatusEOF) {
        return;
    }
    self.status = DLGPlayerStatusPaused;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [self.player pause];
    [self.playPauseButton setImage:[UIImage imageNamed:@"play_button"] forState:UIControlStateNormal];
}

- (void)previousTrack
{
    if (self.status == DLGPlayerStatusClosing) {
        return;
    }
    PlaylistViewController *playlistViewController = [self getPlaylistViewController];
    NSString *url = [playlistViewController previousTrack];
    if (url) {
        self.url = url;
        [self close];
        [self open];
    }
}

- (void)nextTrack
{
    if (self.status == DLGPlayerStatusClosing) {
        return;
    }
    PlaylistViewController *playlistViewController = [self getPlaylistViewController];
    NSString *url = [playlistViewController nextTrack];
    if (url) {
        self.url = url;
        [self close];
        [self open];
    }
}

#pragma mark - position

- (void)setPosition:(double)position
{
    if (self.status == DLGPlayerStatusPaused) {
        [self play];
    }
    
    self.player.position = position;
    self.positionSllder.value = position;
    
    [nowPlayingInfo setObject:[NSNumber numberWithFloat:position] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime]; //currentTrackTime:
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
}

- (double)position
{
    return self.player.position;
}

#pragma mark - NextOperation

- (BOOL)doNextOperation
{
    if (self.nextOperation == DLGPlayerOperationNone) return NO;
    switch (self.nextOperation) {
        case DLGPlayerOperationOpen:
            [self open];
            break;
        case DLGPlayerOperationPlay:
            [self play];
            break;
        case DLGPlayerOperationPause:
            [self pause];
            break;
        case DLGPlayerOperationClose:
            [self close];
            break;
        default:
            break;
    }
    self.nextOperation = DLGPlayerOperationNone;
    return YES;
}

#pragma mark - System notifications

- (void)notifyAppWillEnterForeground:(NSNotification *)notif
{
    if (self.status == DLGPlayerStatusPaused) {
        //[self.player pause]; // after 25 min on pause make nose
    }
}

#pragma mark - Player notifications

- (void)notifyPlayerEOF:(NSNotification *)notif
{
    self.status = DLGPlayerStatusEOF;
    if (self.repeat)
        [self replay];
    else {
        PlaylistViewController *playlistViewController = [self getPlaylistViewController];
        NSString *url = [playlistViewController nextTrack];
        if (url) {
            self.url = url;
            [self close];
            [self open];
        }
        else {
            playlistViewController.trackIndex = -1;
            [playlistViewController.tracksTable reloadData];
            self.url = @"";
            [self close];
        }
    }
}

- (void)notifyPlayerClosed:(NSNotification *)notif
{
    self.status = DLGPlayerStatusClosed;
    [self.loadingActivity stopAnimating];
    [self destroyTimer];
    
    //set first player state
    self.videoBoxView.hidden = YES;
    self.albumCoverView.hidden = NO;
    self.titleLabel.text = @"ArtistShot";
    self.positionSllder.enabled = NO;
    self.positionSllder.value = 0;
    self.positionSllder.maximumValue = 0;
    self.timePassedLabel.text = @"--:--";
    self.timeRemainLabel.text = @"--:--";
    [self.playPauseButton setImage:[UIImage imageNamed:@"play_button"] forState:UIControlStateNormal];
    
    //next operation
    [self doNextOperation];
}

- (void)notifyPlayerOpened:(NSNotification *)notif
{
    __weak typeof(self)weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.loadingActivity stopAnimating];
    });
    
    self.status = DLGPlayerStatusOpened;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf)strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        
        strongSelf.videoBoxView.hidden = !strongSelf.player.hasVideo;
        strongSelf.albumCoverView.hidden = !strongSelf.videoBoxView.hidden;
        
        double durationDouble = strongSelf.player.duration;
        int duration = ceil(durationDouble);
        
        [nowPlayingInfo removeObjectForKey:MPMediaItemPropertyArtist];
        [nowPlayingInfo removeObjectForKey:MPMediaItemPropertyPlaybackDuration];
        [nowPlayingInfo removeObjectForKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
        if (duration > 0) {
            [strongSelf updateTitle];
            [nowPlayingInfo setObject:[NSNumber numberWithFloat:duration] forKey:MPMediaItemPropertyPlaybackDuration]; //Duration
            //[nowPlayingInfo setObject:[NSNumber numberWithBool:NO] forKey:MPNowPlayingInfoPropertyIsLiveStream];
            [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
        }
        else {
            //live (etc. radio)
            strongSelf.timeRemainLabel.text = @"Live";
        }

        strongSelf.positionSllder.enabled = duration > 0;
        strongSelf.positionSllder.value = 0;
        strongSelf.positionSllder.maximumValue = duration;
        strongSelf.updateHUD = YES;
        [strongSelf createTimer];
        //[strongSelf showHUD];
    });

    if (![self doNextOperation]) {
        if (self.autoplay) [self play];
    }
}

- (void)notifyPlayerBufferStateChanged:(NSNotification *)notif
{
    NSDictionary *userInfo = notif.userInfo;
    BOOL state = [userInfo[DLGPlayerNotificationBufferStateKey] boolValue];
    if (state) {
        self.status = DLGPlayerStatusBuffering;
        [self.loadingActivity startAnimating];
    } else {
        self.status = DLGPlayerStatusPlaying;
        [self.loadingActivity stopAnimating];
    }
}

- (void)notifyPlayerError:(NSNotification *)notif
{
    NSDictionary *userInfo = notif.userInfo;
    NSError *error = userInfo[DLGPlayerNotificationErrorKey];

    if ([error.domain isEqualToString:DLGPlayerErrorDomainDecoder]) {
        __weak typeof(self)weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf)strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            [strongSelf.loadingActivity stopAnimating];
            strongSelf.status = DLGPlayerStatusNone;
            strongSelf.nextOperation = DLGPlayerOperationNone;
        });

        NSLog(@"Player decoder error: %@", error);
    }
    else
        if ([error.domain isEqualToString:DLGPlayerErrorDomainAudioManager]) {
            NSLog(@"Player audio error: %@", error);
            // I am not sure what will cause the audio error,
            // if it happens, please issue to me
        }
    
    
    [self showPlayerError:error];
    //[[NSNotificationCenter defaultCenter] postNotificationName:DLGPlayerNotificationError object:self userInfo:notif.userInfo];
}

- (void)showPlayerError:(NSError *)error
{
    BOOL isAudioError = [error.domain isEqualToString:DLGPlayerErrorDomainAudioManager];
    NSString *title = isAudioError ? @"Audio Error" : @"Error";
    NSString *message = error.localizedDescription;
    if (isAudioError) {
        NSError *rawError = error.userInfo[NSLocalizedFailureReasonErrorKey];
        message = [message stringByAppendingFormat:@"\n%@", rawError];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil];
        [alert addAction:ok];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - UI

- (void)initPlayer
{
    self.player = [[DLGPlayer alloc] init];
    UIView *v = self.player.playerView;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [self.videoBoxView addSubview:v];
    
    // Add constraints
    NSDictionary *views = NSDictionaryOfVariableBindings(v);
    NSArray<NSLayoutConstraint *> *ch = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[v]|" options:0 metrics:nil views:views];
    [self.view addConstraints:ch];
    NSArray<NSLayoutConstraint *> *cv = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|[v]|" options:0 metrics:nil views:views];
    [self.videoBoxView addConstraints:cv];
}

- (void)initTapGesutre
{
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTapGesutreRecognizer:)];
    tap.numberOfTapsRequired = 1;
    tap.numberOfTouchesRequired = 1;
    [self.view addGestureRecognizer:tap];
    self.grTap = tap;
}

#pragma mark - Tap gesture action

- (void)onTapGesutreRecognizer:(UITapGestureRecognizer *)recognizer
{
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (UIInterfaceOrientationIsPortrait(orientation)) {
        return;
    }
    
    //only for Landscape
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        if (self.topBarView.hidden)
            [self showHUD];
        else
            [self hideHUD];
    }
}

#pragma mark - Show/Hide HUD

- (void)showHUD
{
    if (animatingHUD) return;

    [self syncHUD:YES];
    animatingHUD = YES;
    self.topBarView.hidden = NO;
    self.playerControlView.hidden = NO;
    self.bottomBarView.hidden = NO;

    __weak typeof(self)weakSelf = self;
    [UIView animateWithDuration:0.5f
                     animations:^{
                         __strong typeof(weakSelf)strongSelf = weakSelf;
                         strongSelf.topBarView.alpha = 1.0f;
                         strongSelf.playerControlView.alpha = 1.0f;
                         strongSelf.bottomBarView.alpha = 1.0f;
                     }
                     completion:^(BOOL finished) {
                         animatingHUD = NO;
                     }];
    [self startTimerForHideHUD];
}

- (void)hideHUD
{
    if (animatingHUD) return;
    animatingHUD = YES;

    __weak typeof(self)weakSelf = self;
    [UIView animateWithDuration:0.5f
                     animations:^{
                         __strong typeof(weakSelf)strongSelf = weakSelf;
                         strongSelf.topBarView.alpha = 0.0f;
                         strongSelf.playerControlView.alpha = 0.0f;
                         strongSelf.bottomBarView.alpha = 0.0f;
                     }
                     completion:^(BOOL finished) {
                         __strong typeof(weakSelf)strongSelf = weakSelf;

                         strongSelf.topBarView.hidden = YES;
                         strongSelf.playerControlView.hidden = YES;
                         strongSelf.bottomBarView.hidden = YES;

                         animatingHUD = NO;
                     }];
    [self stopTimerForHideHUD];
}

#pragma mark - Timer for HideHUD

- (void)startTimerForHideHUD
{
    [self updateTimerForHideHUD];
    if (self.timerForHUD != nil) return;
    self.timerForHUD = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(timerForHideHUD:) userInfo:nil repeats:YES];
}

- (void)stopTimerForHideHUD
{
    if (self.timerForHUD == nil) return;
    [self.timerForHUD invalidate];
    self.timerForHUD = nil;
}

- (void)updateTimerForHideHUD
{
    showHUDTime = [NSDate timeIntervalSinceReferenceDate];
}

- (void)timerForHideHUD:(NSTimer *)timer
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - showHUDTime > 5) {
        [self hideHUD];
        [self stopTimerForHideHUD];
    }
}

#pragma mark - Timer for syncHUD

- (void)createTimer
{
    if (self.timer != nil) return;

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);

    __weak typeof(self)weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        [weakSelf syncHUD];
    });
    dispatch_resume(timer);
    self.timer = timer;
}

- (void)destroyTimer
{
    if (self.timer == nil) return;
    
    dispatch_cancel(self.timer);
    self.timer = nil;
}

@end
