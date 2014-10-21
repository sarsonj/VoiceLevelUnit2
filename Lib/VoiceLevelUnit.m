//
//  Created by sarsonj on 11/3/11.
//
// To change the template use AppCode | Preferences | File Templates.
//



#import <CoreAudio/CoreAudioTypes.h>
#import <AVFoundation/AVFoundation.h>
#include "coreAudioUtils.h"
#import "VoiceLevelUnit.h"
#import "LowpassFilter.h"
#include <mach/mach_time.h>
//#import <CoreAudio/CoreAudio.h>
//#import <MediaPlayer/MediaPlayer.h>




#ifndef TARGET_OS_IPHONE
#import "UIDevice+System.h"
#import "TestFlight.h"
#endif

AudioUnit audioUnit;
AudioStreamBasicDescription audioFormat;
//AudioBufferList bufferList;
AudioComponent inputComponent;
mach_timebase_info_data_t machTimeInfo;






#define kOutputBus  0
#define kInputBus   1


#define kNotRecording       0
#define kWillRecording      2
#define kRecording          3
#define kWillStopRecording  4

#define LOWPASSFILTERTIMESLICE .1

#define DBOFFSET -49.0
#define DBDIV_RECORDING_NORMAL        37
#define DBDIV_RECORDING_SENSITIVE     20

#define MIN_RECORDING_LEVEL 0.25

#define MIN_RECORDING_LEVEL_OFFSET_0 2
#define MIN_RECORDING_LEVEL_OFFSET_1 7
#define MIN_RECORDING_LEVEL_OFFSET_2 14
#define MIN_RECORDING_LEVEL_OFFSET_3 19


@interface VoiceLevelUnit ()
- (void)initAndStartAudioUnit:(VoiceAudioUnitType)type whenDone:(TSBlockWithIntParameter)after;
- (OSStatus)stopAudioUnit;
- (void)cleanUpAudioUnit;


@end

dispatch_queue_t audioManagementQueue;


@implementation VoiceLevelUnit

{
    LowpassFilter *recordingLowpass;
    LowpassFilter *playingLowpass;

    float maxBoosterLevel;
    float   recordingMinLevel;
    int     recorderState;
    UInt64  recordingTimer;
    float decibelsCorrection;
    float recordingLevelDbOffset;
    float oldRelativeVoiceLevel;
    // only sends levels delegate, don't process data...
    BOOL onlyCheckLevels;
    BOOL playBoostEnabled;
    BOOL recordingSensitive;
    BOOL isRecordingEnabled;
    BOOL paused;
    BOOL _audioUnitPaused;
}


SYNTHESIZE_SINGLETON_FOR_CLASS(VoiceLevelUnit)
@synthesize recordingDelegate;
@synthesize sessionDelegate;
@synthesize recordingSensitive;
@synthesize paused;
@synthesize audioUnitPaused = _audioUnitPaused;
@synthesize actualAudioUnit;


-(id)init {
    if ((self = [super init])) {
        audioManagementQueue = dispatch_queue_create("com.tappytaps.babym3g", DISPATCH_QUEUE_SERIAL);
        AVAudioSession *session = [AVAudioSession sharedInstance];

        if (floor(NSFoundationVersionNumber) >= NSFoundationVersionNumber_iOS_6_0) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInterruptionChanged:) name:AVAudioSessionInterruptionNotification object:nil];
        } else {
            session.delegate = self;
        }
        // prefill AudioConvertedSettings...
        // from iLBMtoPCM
        paused = NO;
        isRecordingEnabled = NO;
        onlyCheckLevels = NO;
        recordingSensitive = NO;

        AudioStreamBasicDescription inputFormat;
        AudioStreamBasicDescription outputFormat;
        recordingTimer = 0;

        recordingLowpass = [[LowpassFilter alloc] initWithParam:LOWPASSFILTERTIMESLICE];
        playingLowpass = [[LowpassFilter alloc] initWithParam:LOWPASSFILTERTIMESLICE];

        // setup iLBM to PCM converter
        memset(&inputFormat, 0, sizeof(inputFormat));
        memset(&outputFormat, 0, sizeof(outputFormat));
//        inputFormat.mFormatID = kAudioFormatiLBC;
        inputFormat.mFormatID = kAudioFormatiLBC;

        inputFormat.mChannelsPerFrame = 1;
        inputFormat.mSampleRate = 8000.0;
        UInt32 propSize = sizeof(inputFormat);
        CheckError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL,
                                          &propSize, &inputFormat), "AudioFormatGetProperty failed");
        outputFormat.mSampleRate = kPreferedFrequency;
        outputFormat.mFormatID = kAudioFormatLinearPCM;
        outputFormat.mFormatFlags = /*kAudioFormatFlagIsBigEndian |*/ kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        outputFormat.mBitsPerChannel = 16;
        outputFormat.mChannelsPerFrame = 1;
        outputFormat.mFramesPerPacket = 1;
        outputFormat.mBytesPerFrame = BYTES_PER_FRAME;
        outputFormat.mBytesPerPacket = 2;
        propSize = sizeof(outputFormat);
        CheckError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL,
                                          &propSize, &outputFormat), "AudioFormatGetProperty failed");

        mach_timebase_info(&machTimeInfo);
        
        maxBoosterLevel = MAX_BOOST_LEVEL_PARENT_STATION;
        recordingMinLevel = MIN_RECORDING_LEVEL;
        [self updateRecordingSensitivitySettings];

        recorderState = kNotRecording;

        // for compatibility with older versions of Baby Monitor 3G - default level for player set to most sensitive
        playingLevelDbOffset = MIN_RECORDING_LEVEL_OFFSET_0;

        self.audioActionsQueue = [[NSOperationQueue alloc] init];
        self.audioActionsQueue.maxConcurrentOperationCount = 1;
    }
    return self;
}


#pragma mark Properties

-(float)dbCorrectionByVoiceSensitivitySettings:(int)sensitivitySettings {
    float toRet;
    switch (sensitivitySettings) {
        case 0:
            toRet = MIN_RECORDING_LEVEL_OFFSET_0;
            break;
        case 1:
            toRet = MIN_RECORDING_LEVEL_OFFSET_1;
            break;
        case 2:
            toRet = MIN_RECORDING_LEVEL_OFFSET_2;
            break;
        case 3:
            toRet = MIN_RECORDING_LEVEL_OFFSET_3;
            break;
        default:
            toRet = MIN_RECORDING_LEVEL_OFFSET_0;
            break;
    }
    return toRet;
}

- (void)updateRecordingSensitivitySettings {
    int minRecordingSetting = 1;
    recordingLevelDbOffset = [self dbCorrectionByVoiceSensitivitySettings:minRecordingSetting];
}

-(void)setSessionForPlayback {
        dispatch_async(audioManagementQueue, ^{
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
            [self routeAudioToSpeaker];
        });
}

-(void)setSessionForRecording {
        dispatch_async(audioManagementQueue, ^{
            [[AVAudioSession sharedInstance] setActive:YES error:nil];
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
            [self routeAudioToSpeaker];
            [[AVAudioSession sharedInstance] setMode:AVAudioSessionModeVoiceChat error:nil];
        });
}


#pragma mark Audio unit callbacks
static double countRelativeVoiceLevel(VoiceLevelUnit *babyAudioUnit, float maxVoiceLevel, bool forceSensitive, bool forPlaying) {
    float decibelOffset = MIN_RECORDING_LEVEL_OFFSET_0;
    if (forPlaying) {
        decibelOffset = babyAudioUnit->playingLevelDbOffset;                        
    } else {
        decibelOffset = babyAudioUnit->recordingLevelDbOffset;
    }
    
    Float32 sampleDB = 20.0*log10(maxVoiceLevel) + DBOFFSET  + babyAudioUnit->decibelsCorrection - decibelOffset;
    if (sampleDB < 0) {
        sampleDB = 0;
    }

    double relativeVoiceLevel = 0;
    if (babyAudioUnit->recordingSensitive || forceSensitive) {
        relativeVoiceLevel = fabs(sampleDB) / fabs(DBDIV_RECORDING_SENSITIVE + decibelOffset /*- babyAudioUnit->recordingLevelDbOffset*/);
    } else {
        relativeVoiceLevel = fabs(sampleDB) / fabs(DBDIV_RECORDING_NORMAL + decibelOffset);
    }
    relativeVoiceLevel = relativeVoiceLevel > 1? 1.0: relativeVoiceLevel;
    return relativeVoiceLevel;
}

static OSStatus playbackCallback(void *inRefCon,
								 AudioUnitRenderActionFlags *ioActionFlags,
								 const AudioTimeStamp *inTimeStamp,
								 UInt32 inBusNumber,
								 UInt32 inNumberFrames,
								 AudioBufferList *ioData) {
    return noErr;
}


/**
* Runs always on baby monitor side - at least check voice level
*/
static OSStatus recordingCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    {


        @autoreleasepool {

            VoiceLevelUnit *babyAudioUnit = (__bridge VoiceLevelUnit *)inRefCon;
            // We check if recording enabled this way
            // probably better than stoping / starting queue again and again
            if (!babyAudioUnit->isRecordingEnabled)
                return 0;

            AudioBufferList list;
            list.mNumberBuffers = 1;

            list.mBuffers[0].mData = NULL;
            list.mBuffers[0].mDataByteSize = 2 * inNumberFrames;
            list.mBuffers[0].mNumberChannels = 1;
            ioData = &list;

            AudioUnitRender(audioUnit,
                                     ioActionFlags,
                                     inTimeStamp,
                                     inBusNumber,
                                     inNumberFrames,
                    ioData);
            Float32 maxVoiceLevel = 0;
            double relativeVoiceLevel = 0;
            for (int i=0; i<ioData->mNumberBuffers; i++) {
                AudioBuffer buffer = ioData->mBuffers[i];
                // count voice level info
            SInt16* samples = (SInt16*)(buffer.mData);
            int samples_size =buffer.mDataByteSize;
                for (int f=0; f< samples_size / 2; f++) {

                    Float32 absoluteValueOfSampleAmplitude = abs(samples[f]);
                    if (absoluteValueOfSampleAmplitude > maxVoiceLevel) {
                        maxVoiceLevel = absoluteValueOfSampleAmplitude;
                    }
                }

                maxVoiceLevel = [babyAudioUnit->recordingLowpass addNextValueToFilter:maxVoiceLevel];
                double relativeVoiceLevelLatest = countRelativeVoiceLevel(babyAudioUnit, babyAudioUnit->recordingLowpass.latestValue, false, false);
                double relativeVoiceLevelFiltered = countRelativeVoiceLevel(babyAudioUnit, maxVoiceLevel, false, false);
                relativeVoiceLevel = MAX(relativeVoiceLevelLatest, relativeVoiceLevelFiltered);
            }


            if (babyAudioUnit->recordingDelegate != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [babyAudioUnit->recordingDelegate recordingUpdateVoiceLevel:relativeVoiceLevel];
                });
            }

        }
    }
    return noErr;
}


#pragma mark Audio Unit initialization
/**
* Init audio session for both playback & recording
*/
-(void)initAudioSession {
#if TARGET_OS_IPHONE
    AVAudioSession* session = [AVAudioSession sharedInstance];
        if ([session respondsToSelector:@selector(setCategory:withOptions:error:)]) {
            [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:nil];
        } else {
            [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
            [self routeAudioToSpeaker];
        }
    [session setActive:YES error:nil];
#endif
}

-(void)routeAudioToSpeaker {
    dispatch_async(audioManagementQueue, ^{
        UInt32 doChangeDefaultRoute = 1;
        AudioSessionSetProperty (
                kAudioSessionProperty_OverrideCategoryDefaultToSpeaker,
                sizeof (doChangeDefaultRoute),
                &doChangeDefaultRoute
        );
    });
}


/**
* prepares audio unit, don't start it
*/
// TODO: OSStatus error handing!
- (void)prepareAudioUnitType:(VoiceAudioUnitType)uType whenDone:(TSBasicBlock)after  {
    dispatch_async(audioManagementQueue, ^{

        actualAudioUnit = uType;

        OSStatus status;
        int counter = 0;
        do {
            memset(&audioUnit, 0, sizeof(AudioComponentInstance));

            BOOL enableMic = 1;
            AudioComponentDescription desc;
            desc.componentType = kAudioUnitType_Output;
            if (enableMic) {
                 desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
            } else {
            }
            desc.componentFlags = 0;
            desc.componentFlagsMask = 0;
            desc.componentManufacturer = kAudioUnitManufacturer_Apple;

            // Get component
            memset(&inputComponent, 0, sizeof(AudioComponent));
            inputComponent = AudioComponentFindNext(NULL, &desc);
            // Get audio units
            status = AudioComponentInstanceNew(inputComponent, &audioUnit);
            CheckError(status, "CreateNewInstance");
            UInt32 enable = 1;


            if (enableMic) {
                enable = 1;
            } else {
                enable = 0;
            }

            // Enable unit for recording


            if (enableMic) {
                status = AudioUnitSetProperty(audioUnit,
                        kAudioOutputUnitProperty_EnableIO,
                        kAudioUnitScope_Input,
                        kInputBus,
                        &enable,
                        sizeof(enable));
                CheckError(status, "SetPropertyPlayback");

            }

            // enable unit for playing
            enable = 1;
            status = AudioUnitSetProperty(audioUnit,
                    kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Output,
                    kOutputBus,
                    &enable,
                    sizeof(enable));
            CheckError(status, "SetPropertyRecording");
            // Describe format

            memset(&audioFormat, 0, sizeof(AudioStreamBasicDescription));

            size_t bytesPerSample = 2;
            audioFormat.mSampleRate			= kPreferedFrequency;
            audioFormat.mFormatFlags		= kAudioFormatFlagIsSignedInteger | /*kAudioFormatFlagsCanonical |*/ kAudioFormatFlagIsPacked;

            audioFormat.mFormatID			= kAudioFormatLinearPCM;



    //    audioFormat.mFormatFlags = kAudioFormatFlagsAudioUnitCanonical;
            audioFormat.mFramesPerPacket	= 1;
            audioFormat.mChannelsPerFrame	= 1;
            audioFormat.mBitsPerChannel		= bytesPerSample * 8;
            audioFormat.mBytesPerPacket		= bytesPerSample;
            audioFormat.mBytesPerFrame		= bytesPerSample;



            //Apply format for both input / output
            status = AudioUnitSetProperty(audioUnit,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Input,
                    kOutputBus,
                    &audioFormat,
                    sizeof(audioFormat));
            CheckError(status, "ApplyFormat1");



            if (enableMic) {
                status = AudioUnitSetProperty(audioUnit,
                        kAudioUnitProperty_StreamFormat,
                        kAudioUnitScope_Output,
                        kInputBus,
                        &audioFormat,
                        sizeof(audioFormat));
                CheckError(status, "ApplyFormat2");
            }

            // Set up the playback  callback
            AURenderCallbackStruct callbackStruct;
            callbackStruct.inputProc = playbackCallback;
            //set the reference to "self" this becomes *inRefCon in the playback callback
            callbackStruct.inputProcRefCon = (__bridge void *)(self);

            status = AudioUnitSetProperty(audioUnit,
                    kAudioUnitProperty_SetRenderCallback,
                    kAudioUnitScope_Global,
                    kOutputBus,
                    &callbackStruct,
                    sizeof(callbackStruct));
            CheckError(status, "Callback1");
            // setup recording callback

            AURenderCallbackStruct callbackInputStruts;
            callbackInputStruts.inputProc = recordingCallback;
            callbackInputStruts.inputProcRefCon = (__bridge void *)(self);

            if (enableMic) {
                status = AudioUnitSetProperty(audioUnit,
                        kAudioOutputUnitProperty_SetInputCallback,
                        kAudioUnitScope_Global,
                        kInputBus,
                        &callbackInputStruts,
                        sizeof(callbackInputStruts));
                CheckError(status, "Callback2");
            }





            status = AudioUnitInitialize(audioUnit);

            counter++;
        } while (status != 0 && counter < 4);
        CheckError(status, "Start");





        // voice processing
        // call callback
        if (after != nil) {
            dispatch_async(dispatch_get_main_queue(), after);
        }
    });
}

/**
* Starts audio unit
*/
-(OSStatus)startAudioUnitWhenDone:(TSBlockWithIntParameter)after {
    dispatch_async(audioManagementQueue, ^{
    // when already in Playback only and wants to start AudioSession - switch to Playback & recording
        
        
        AVAudioSession *currentSession = [AVAudioSession sharedInstance];
        NSString* currentSessionCategory = currentSession.category;

        EmptyBlock startUnitBlock = ^{
            [self configureAudioSessionForRecordingAndPlayback:^{
                oldRelativeVoiceLevel = -1;
                OSStatus status = AudioOutputUnitStart(audioUnit);

                if (status != 0) {
                    if ([sessionDelegate respondsToSelector:@selector(errorWhenInit:)]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [sessionDelegate errorWhenInit:status];
                        });
                    }
                } else {
                    if ([sessionDelegate respondsToSelector:@selector(audioUnitStarted)]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [sessionDelegate audioUnitStarted];
                        });
                    }
                }
                if (after != nil) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        after(status);
                    });
                }
            }];
        };

        
        if (![currentSessionCategory isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
            [self configureAudioSessionForRecordingAndPlayback:startUnitBlock];
        } else {

            startUnitBlock();
        }
    });
    return 0;
}

/**
* Stop Audio Unit
*/
-(OSStatus)stopAudioUnit {
	OSStatus status = AudioOutputUnitStop(audioUnit);
	return status;
}

/**
* Cleanup
*/
-(void)cleanUpAudioUnit {
    OSStatus status;
    status = AudioUnitUninitialize(audioUnit);
    CheckError(status, "Uninitialize");
    status = AudioComponentInstanceDispose(audioUnit);
    CheckError(status, "Dispose");
    audioUnit = nil;
}




- (void)initAndStartAudioUnit:(VoiceAudioUnitType)type whenDone:(TSBlockWithIntParameter)after {

    TSBasicBlock startAUBlock = ^{
        #if TARGET_IPHONE_SIMULATOR
        #else
            [self prepareAudioUnitType:type whenDone:^{
                [self startAudioUnitWhenDone:after];
            }];
        #endif
    };
    if (type != actualAudioUnit && actualAudioUnit != kUnitTypeNone) {
        [self stopAudioWhenDone:startAUBlock];
    } else {
        startAUBlock();
    }
}

#pragma mark High level public functions

- (void)configureAudioSessionForRecordingAndPlayback:(TSBasicBlock)afterSessionSet {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSString* newSession;
    newSession = AVAudioSessionCategoryPlayAndRecord;
        if ([session respondsToSelector:@selector(setCategory:withOptions:error:)]) {
            [session setCategory:newSession withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:nil];
        } else {
            [session setCategory:newSession error:nil];
            [self routeAudioToSpeaker];
        }
    [session setMode:AVAudioSessionModeVoiceChat error:nil];
    dispatch_async(audioManagementQueue, ^{
        if (afterSessionSet != nil) {
            afterSessionSet();
        };
    });
}


- (void)startRecording {
    if (!isRecordingEnabled) {
        self->recorderState = kNotRecording;
        isRecordingEnabled = YES;
        [self setSessionForRecording];
    }
}

- (void)stopRecording {
    if (isRecordingEnabled) {
        isRecordingEnabled = NO;
        [self setSessionForPlayback];
    }
}

- (void)startAudioForType:(VoiceAudioUnitType)type after:(EmptyBlock)after {
    dispatch_async(audioManagementQueue, ^{
        @autoreleasepool {
            paused = NO;
            if (actualAudioUnit == kUnitTypeNone) {
                [playingLowpass reset];
                VoiceAudioUnitType unitType = type;
                [self initAndStartAudioUnit:unitType whenDone:^(int result) {
                    if (after != nil) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            after();
                        });
                    }
                }];
            } else {
                if (after != nil) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        after();
                    });
                }
            }
        }
    });
}

- (void)stopAudioWhenDone:(TSBasicBlock)after {
    dispatch_async(audioManagementQueue, ^{
        @autoreleasepool {
            if (actualAudioUnit != kUnitTypeNone) {
                [self stopAudioUnit];
                [self cleanUpAudioUnit];
                // cleanup playing buffer
                actualAudioUnit = kUnitTypeNone;
                isRecordingEnabled = NO;
                if (after != nil) {
                    dispatch_async(dispatch_get_main_queue(), after);
                }

            }
        }
    });
}

-(void)pauseAudioUnit {
    if (actualAudioUnit != kUnitTypeNone && !paused) {
        dispatch_async(audioManagementQueue, ^{
            @autoreleasepool {
                     [self stopAudioUnit];
            }
        });
        paused = YES;
    }
}

-(void)resumeAudioUnit {
    if (actualAudioUnit != kUnitTypeNone && paused) {
        dispatch_async(audioManagementQueue, ^{
            @autoreleasepool {
                [self startAudioUnitWhenDone:^(int error) {
                    if (error != 0) {

                    } else {
                        paused = NO;
                    }
                }];
            }
        });
    }
}


#pragma mark AVAudioSessionDelegate

#if TARGET_OS_IPHONE

-(void)audioInterruptionChanged:(NSNotification *)notification {
    if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue] == AVAudioSessionInterruptionTypeBegan) {
        [self beginInterruption];
    } else if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue] == AVAudioSessionInterruptionTypeEnded) {
        [self endInterruption];
    }
}

- (void)beginInterruption {
    [self pauseAudioUnit];
    self.audioUnitPaused = YES;
    if ([sessionDelegate respondsToSelector:@selector(beginInterruption)]) {
        [sessionDelegate beginInterruption];
    }
}

- (void)endInterruption {
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [self resumeAudioUnit];
    self.audioUnitPaused = NO;
    if ([sessionDelegate respondsToSelector:@selector(endInterruption)]) {
        [sessionDelegate endInterruption];
    }
}

#endif

#pragma mark Dealloc stuff

- (void)dealloc {
    audioManagementQueue = NULL;
    [self stopAudioUnit];
    [self cleanUpAudioUnit];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


@end