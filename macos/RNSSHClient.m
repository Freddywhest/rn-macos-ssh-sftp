#import "RNSSHClient.h"

#import <React/RCTLog.h>
#import <React/RCTConvert.h>

#import "NMSSH/NMSSH.h"
#import "NMSSH/NMSFTP.h"

@implementation RNSSHClient {
    NSMutableDictionary *_clientPool;
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

#pragma mark - Client Pool

- (NSMutableDictionary *)clientPool
{
    if (!_clientPool) {
        _clientPool = [NSMutableDictionary new];
    }
    return _clientPool;
}

- (SSHClient *)clientForKey:(NSString *)key
{
    return self.clientPool[key];
}

#pragma mark - Delegate Events

- (void)shellEvent:(NSString *)event withKey:(NSString *)key
{
    [self sendEventWithName:@"Shell"
                       body:@{
                           @"key": key ?: @"",
                           @"data": event ?: @""
                       }];
}

- (void)downloadProgressEvent:(int)progress withKey:(NSString *)key
{
    [self sendEventWithName:@"DownloadProgress"
                       body:@{
                           @"key": key ?: @"",
                           @"progress": @(progress)
                       }];
}

- (void)uploadProgressEvent:(int)progress withKey:(NSString *)key
{
    [self sendEventWithName:@"UploadProgress"
                       body:@{
                           @"key": key ?: @"",
                           @"progress": @(progress)
                       }];
}

#pragma mark - Connection

RCT_EXPORT_METHOD(connectToHost:(NSString *)host
                  port:(NSInteger)port
                  withUsername:(NSString *)username
                  passwordOrKey:(id)passwordOrKey
                  withKey:(NSString *)key
                  withCallback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(self.methodQueue, ^{
        NMSSHSession *session =
            [[NMSSHSession alloc] initWithHost:host
                                   andUsername:username];

        [session connect];

        if (!session.connected) {
            callback(@[@{ @"message": @"Connection failed" }]);
            return;
        }

        BOOL authenticated = NO;

        if ([passwordOrKey isKindOfClass:[NSString class]]) {
            authenticated =
                [session authenticateByPassword:passwordOrKey];
        }
        else if ([passwordOrKey isKindOfClass:[NSDictionary class]]) {
            NSString *privateKey = passwordOrKey[@"privateKey"];
            NSString *publicKey  = passwordOrKey[@"publicKey"];
            NSString *passphrase = passwordOrKey[@"passphrase"];

            authenticated =
                [session authenticateByPublicKey:publicKey
                                       privateKey:privateKey
                                      andPassword:passphrase];
        }

        if (!authenticated || !session.authorized) {
            [session disconnect];
            callback(@[@{ @"message": @"Authentication failed" }]);
            return;
        }

        SSHClient *client = [SSHClient new];
        client._session = session;
        client._key = key;
        client.delegate = self;

        self.clientPool[key] = client;

        callback(@[[NSNull null]]);
    });
}

#pragma mark - Execute

RCT_EXPORT_METHOD(execute:(NSString *)command
                  withKey:(NSString *)key
                  withCallback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(self.methodQueue, ^{
        SSHClient *client = [self clientForKey:key];
        if (!client) {
            callback(@[@{ @"message": @"Client not found" }]);
            return;
        }

        NSError *error = nil;
        NSString *output =
            [client._session.channel execute:command
                                       error:&error
                                     timeout:@10];

        if (error) {
            callback(@[@{
                @"code": @(error.code),
                @"message": error.localizedDescription
            }]);
        } else {
            callback(@[[NSNull null], output ?: @""]);
        }
    });
}

@end
