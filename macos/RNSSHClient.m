#import <React/RCTUtils.h>
#import "RNSSHClient.h"
#import "SSHClient.h"

@implementation RNSSHClient {
    NSMutableDictionary* _clientPool;
}

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue
{
    return dispatch_queue_create("reactnative.sshclient", DISPATCH_QUEUE_SERIAL);
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"Shell", @"DownloadProgress", @"UploadProgress"];
}

- (NSMutableDictionary*) clientPool {
    if (!_clientPool) {
        _clientPool = [NSMutableDictionary new];
    }
    return _clientPool;
}

- (SSHClient*) clientForKey:(nonnull NSString*)key {
    return [[self clientPool] objectForKey:key];
}

- (BOOL)isConnected:(NMSSHSession *)session
       withCallback:(RCTResponseSenderBlock)callback {
    if (session && session.isConnected && session.isAuthorized) {
        return true;
    } else {
        RCTLogWarn(@"Session not connected");
        if (callback) {
            callback(@[@"Session not connected"]);
        }
        return false;
    }
}

- (BOOL)isSFTPConnected:(NMSFTP *)sftpSession
           withCallback:(RCTResponseSenderBlock)callback {
    if (sftpSession && sftpSession.connected) {
        return true;
    } else {
        RCTLogWarn(@"SFTP not connected");
        if (callback) {
            callback(@[@"SFTP not connected"]);
        }
        return false;
    }
}

RCT_EXPORT_METHOD(connectToHost:(NSString *)host
                  port:(NSInteger)port
                  withUsername:(NSString *)username
                  passwordOrKey:(id)passwordOrKey
                  withKey:(nonnull NSString*)key
                  withCallback:(RCTResponseSenderBlock)callback)
{
    // Ensure we're on the method queue
    dispatch_async(self.methodQueue, ^{
        NSError *error = nil;
        NMSSHSession* session = [NMSSHSession connectToHost:host
                                                       port:port
                                               withUsername:username
                                                      error:&error];
        
        if (error) {
            RCTLogError(@"Connection error: %@", error);
            callback(@[@{@"code": @(error.code), @"message": error.localizedDescription}]);
            return;
        }
        
        if (session && session.connected) {
            BOOL authenticated = NO;
            
            if ([passwordOrKey isKindOfClass:[NSString class]]) {
                authenticated = [session authenticateByPassword:passwordOrKey error:&error];
            } else if ([passwordOrKey isKindOfClass:[NSDictionary class]]) {
                NSString *privateKey = [RCTConvert NSString:passwordOrKey[@"privateKey"]];
                NSString *publicKey = [RCTConvert NSString:passwordOrKey[@"publicKey"]];
                NSString *passphrase = [RCTConvert NSString:passwordOrKey[@"passphrase"]];
                
                if (privateKey) {
                    authenticated = [session authenticateByInMemoryPublicKey:publicKey
                                                                  privateKey:privateKey
                                                                 andPassword:passphrase
                                                                       error:&error];
                }
            }
            
            if (authenticated && session.authorized) {
                SSHClient* client = [[SSHClient alloc] init];
                client._session = session;
                client._key = key;
                [[self clientPool] setObject:client forKey:key];
                RCTLogInfo(@"Session connected to %@", host);
                callback(@[[NSNull null]]);
            } else {
                [session disconnect];
                NSString *errorMsg = error ? error.localizedDescription : @"Authentication failed";
                RCTLogError(@"Authentication failed: %@", errorMsg);
                callback(@[@{@"code": @-1, @"message": errorMsg}]);
            }
        } else {
            NSString *errorMsg = @"Failed to establish connection";
            RCTLogError(@"%@ to host %@", errorMsg, host);
            callback(@[@{@"code": @-1, @"message": errorMsg}]);
        }
    });
}

// Helper method for error handling
- (id)formatError:(NSError *)error {
    if (!error) {
        return [NSNull null];
    }
    return @{
        @"code": @(error.code),
        @"message": error.localizedDescription ?: @"Unknown error",
        @"domain": error.domain
    };
}

// Update execute method to use new error handling
RCT_EXPORT_METHOD(execute:(NSString *)command
                  withKey:(nonnull NSString*)key
                  withCallback:(RCTResponseSenderBlock)callback) {
    dispatch_async(self.methodQueue, ^{
        SSHClient* client = [self clientForKey:key];
        if (!client) {
            callback(@[@{@"code": @-1, @"message": @"Unknown client"}]);
            return;
        }
        
        NMSSHSession* session = client._session;
        if (![self isConnected:session withCallback:callback]) {
            return;
        }
        
        NSError* error = nil;
        NSString* response = [session.channel execute:command error:&error timeout:@10];
        if (error) {
            RCTLogError(@"Error executing command: %@", error);
            callback(@[[self formatError:error]]);
        } else {
            callback(@[[NSNull null], response ?: @""]);
        }
    });
}
