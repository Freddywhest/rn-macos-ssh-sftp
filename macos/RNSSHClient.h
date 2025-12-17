#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

#import "SSHClient.h"

@interface RNSSHClient : RCTEventEmitter <RCTBridgeModule, SSHClientDelegate>

- (void)shellEvent:(NSString *)event
           withKey:(NSString *)key;

- (void)downloadProgressEvent:(int)progress
                      withKey:(NSString *)key;

- (void)uploadProgressEvent:(int)progress
                    withKey:(NSString *)key;

@end
