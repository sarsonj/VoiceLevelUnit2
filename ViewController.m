//
//  ViewController.m
//  testAudioUnit
//
//  Created by JS on 21/10/14.
//  Copyright (c) 2014 TappyTaps. All rights reserved.
//

#import "ViewController.h"
#import "VoiceLevelUnit.h"
#import "VoiceLevelNotifier.h"

@interface ViewController () {
    VoiceLevelNotifier *notifier;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    notifier = [[VoiceLevelNotifier alloc] init];
    notifier.voiceLevelDelegate = self;
    [notifier startMonitoring];

}

- (void)recordingUpdateVoiceLevel:(float)level {

}

- (void)updateFromVoiceNotifier:(float)level {
    NSLog(@"Voice level: %f", level);
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
