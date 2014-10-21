#ifndef _CORE_AUDIO_UTILS_H
#define _CORE_AUDIO_UTILS_H

#include <AudioToolbox/AudioToolbox.h>
#include <Foundation/Foundation.h>

extern void CheckError(OSStatus error, const char *operation);
extern int CountAudioBufferSize(const AudioStreamBasicDescription *format,  float seconds);


#endif