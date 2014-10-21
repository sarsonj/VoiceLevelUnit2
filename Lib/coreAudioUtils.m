#include "coreAudioUtils.h"


void CheckError(OSStatus error, const char *operation) {
    if (error == noErr) return;
    char errorString[20] = {};
    // see if it appears to be a 4-char-code
    *(UInt32 *) (errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else
        // no, format it as an integer
        sprintf(errorString, "%d", (int) error);

    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    NSLog(@"Audio errror %s (%s)", operation, errorString);
    exit(1);
}



int CountAudioBufferSize(const AudioStreamBasicDescription *format,  float seconds) {
    int packets, frames, bytes = 0;

    frames = (int) ceil(seconds * format->mSampleRate);

    if (format->mBytesPerFrame > 0)                        // 1
        bytes = frames * format->mBytesPerFrame;
    else {
        UInt32 maxPacketSize = 0;
        if (format->mBytesPerPacket > 0)                // 2
            maxPacketSize = format->mBytesPerPacket;
        else {

        }
        if (format->mFramesPerPacket > 0)
            packets = frames / format->mFramesPerPacket;     // 4
        else
            // worst-case scenario: 1 frame in a packet
            packets = frames;                            // 5

        if (packets == 0)        // sanity check
            packets = 1;
        bytes = packets * maxPacketSize;                // 6
    }
    return bytes;
}
