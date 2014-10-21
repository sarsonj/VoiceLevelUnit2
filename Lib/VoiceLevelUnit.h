//
//  Created by sarsonj on 11/3/11.
//
// To change the template use AppCode | Preferences | File Templates.
//


#define kPreferedFrequency  16000

// common types
typedef void (^TSBasicBlock)(void);
typedef void (^TSBlockWithIntParameter)(int);
typedef void (^EmptyBlock)();
typedef BOOL (^BoolBlock)();



#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "SynthesizeSingleton.h"


#define MAX_BOOST_LEVEL_PARENT_STATION 20
#define BYTES_PER_FRAME 2



typedef enum VoiceAudioUnitType {
    kUnitTypeNone = 0,
    kUnitTypeNoVoiceProcessing,
    kUnitTypeWithVoiceProcessing
} VoiceAudioUnitType;

@protocol BabyAudioUnitRecordingDelegate
    -(void)recordingUpdateVoiceLevel:(float)level;
@end


@protocol VoiceSessionDelegate <NSObject>
@optional
    -(void)beginInterruption;
    -(void)endInterruption;
    -(void)errorWhenInit:(SInt32)code;
    -(void)audioUnitStarted;
@end

@interface VoiceLevelUnit : NSObject<AVAudioSessionDelegate>
{
    VoiceAudioUnitType actualAudioUnit;
    BOOL voiceProcessingEnabled;
    BOOL startWithPlaybackMode;
@public
    float playingLevelDbOffset;
}

@property(nonatomic, weak) NSObject<BabyAudioUnitRecordingDelegate>* recordingDelegate;
@property(nonatomic, weak) NSObject<VoiceSessionDelegate> *sessionDelegate;
@property(nonatomic) BOOL recordingSensitive;
@property(nonatomic) BOOL paused;
@property VoiceAudioUnitType actualAudioUnit;
@property BOOL audioUnitPaused;

@property(nonatomic, strong) NSOperationQueue *audioActionsQueue;

#if TARGET_OS_REALMAC
// when enabled, no VoiceProcessingIO is started, so that we have to start it when wants recording
// used on Parent Station on Mac to avoid interference with other Mac audio
@property BOOL specialMacRecordingVariant;

#endif

#if RECORDING_SERVICE_COUNTER
@property int recordingServiceCounter;
#endif

+ (id)sharedVoiceLevelUnit;

- (float)dbCorrectionByVoiceSensitivitySettings:(int)sensitivitySettings;

- (void)updateRecordingSensitivitySettings;


- (void)setSessionForPlayback;

- (void)setSessionForRecording;

// Audio unit control
- (void)initAudioSession;

- (void)routeAudioToSpeaker;

//- (void)enableVoiceProcessingFunctions:(BOOL)enable;


-(void)startRecording;
-(void)stopRecording;

- (void)startAudioForType:(VoiceAudioUnitType)type after:(EmptyBlock)after;

- (void)stopAudioWhenDone:(TSBasicBlock)after;

- (void)resumeAudioUnit;


- (void)configureAudioSessionForRecordingAndPlayback:(TSBasicBlock)afterSessionSet;

@end