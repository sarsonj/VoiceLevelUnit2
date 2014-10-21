//
//  ViewController.h
//  testAudioUnit
//
//  Created by JS on 21/10/14.
//  Copyright (c) 2014 TappyTaps. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "VoiceLevelUnit.h"
#import "VoiceLevelNotifier.h"

@interface ViewController : UIViewController <BabyAudioUnitRecordingDelegate, VoiceLevelNotifierDelegate>


@end

