//
//  VoiceLevelNotifier.h
//  testAudioUnit
//
//  Created by JS on 21/10/14.
//  Copyright (c) 2014 TappyTaps. All rights reserved.
//


#import <Foundation/Foundation.h>
#import "VoiceLevelUnit.h"


@protocol VoiceLevelNotifierDelegate
-(void)updateFromVoiceNotifier:(float)level;
@end

@interface VoiceLevelNotifier : NSObject <BabyAudioUnitRecordingDelegate>

@property (weak) NSObject<VoiceLevelNotifierDelegate> *voiceLevelDelegate;
@property (weak) VoiceLevelNotifier* weakSelf;

- (void)startMonitoring;
- (void)stopMonitoring;
@end