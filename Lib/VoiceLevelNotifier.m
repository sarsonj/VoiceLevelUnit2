//
//  VoiceLevelNotifier.m
//  testAudioUnit
//
//  Created by JS on 21/10/14.
//  Copyright (c) 2014 TappyTaps. All rights reserved.
//

#import "VoiceLevelNotifier.h"
#import "VoiceLevelUnit.h"

@implementation VoiceLevelNotifier {
    VoiceLevelUnit *audioUnit;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        audioUnit = [VoiceLevelUnit sharedVoiceLevelUnit];
    }
    return self;
}


-(void)startMonitoring {
    [audioUnit startAudioForType:kUnitTypeWithVoiceProcessing after:^{
        audioUnit.recordingDelegate = self;
        [audioUnit startRecording];

    }];
}

- (void)recordingUpdateVoiceLevel:(float)level {
    if ([_voiceLevelDelegate respondsToSelector:@selector(updateFromVoiceNotifier:)]) {
        [_voiceLevelDelegate updateFromVoiceNotifier:level];
    }
}


-(void)stopMonitoring {
    [audioUnit stopAudioWhenDone:^{

    }];
}

@end
