#import "RNSSHClient.h"
#import <React/RCTLog.h>
#import <React/RCTConvert.h>
#import "NMSSH/NMSSH.h"
#import "NMSSH/NMSFTP.h"

@implementation RNSSHClient {
    NSMutableDictionary *_clientPool;
}

RCT_EXPORT_MODULE();

#pragma mark - Queue

- (dispatch_queue_t)methodQueue
{
    return dispatch_queue_create("reactnative.sshclient", DISPATCH_QUEUE_SERIAL);
}

#pragma mark - Events

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

#pragma mark - Delegate Callbacks

- (void)shellEvent:(NSString *)event withKey:(NSString *)key
{
    [self sendEventWithName:@"Shell"
                       body:@{ @"key": key ?: @"", @"data": event ?: @"" }];
}

- (void)downloadProgressEvent:(float)progress withKey:(NSString *)key
{
    [self sendEventWithName:@"DownloadProgress"
                       body:@{ @"key": key ?: @"", @"progress": @(progress) }];
}

- (void)uploadProgressEvent:(float)progress withKey:(NSString *)key
{
    [self sendEventWithName:@"UploadProgress"
                       body:@{ @"key": key ?: @"", @"progress": @(progress) }];
}

#pragma mark - CONNECT
RCT_EXPORT_METHOD(connectToHost:(NSString *)host
                  port:(NSInteger)port
                  withUsername:(NSString *)username
                  passwordOrKey:(id)passwordOrKey
                  timeout:(NSInteger)timeout
                  withKey:(NSString *)key
                  withCallback:(RCTResponseSenderBlock)callback)
{
    // Run NMSSH on a background thread to prevent blocking JS
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            NSString *hostWithPort = [NSString stringWithFormat:@"%@:%ld", host, (long)port];
            NMSSHSession *session = [[NMSSHSession alloc] initWithHost:hostWithPort
                                                          andUsername:username];
            
            // Set timeout (in seconds)
            session.timeout = @(timeout > 0 ? timeout : 15);

            [session connect];

            if (!session.connected) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    callback(@[@{@"message": @"Connection failed"}]);
                });
                return;
            }

            BOOL authenticated = NO;
            NSError *fileError = nil;

            // ---------------- PASSWORD ----------------
            if ([passwordOrKey isKindOfClass:[NSString class]]) {
                authenticated = [session authenticateByPassword:passwordOrKey];
            }

            // ---------------- PUBLIC KEY ----------------
            else if ([passwordOrKey isKindOfClass:[NSDictionary class]]) {
                NSString *privateKey = passwordOrKey[@"privateKey"];
                NSString *publicKey  = passwordOrKey[@"publicKey"];
                NSString *passphrase = passwordOrKey[@"passphrase"] ?: @"";

                if (!privateKey.length) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        callback(@[@{@"message": @"Private key missing"}]);
                    });
                    return;
                }

                // Write keys to temp files
                NSString *tmpDir = NSTemporaryDirectory();
                NSString *privPath = [tmpDir stringByAppendingPathComponent:
                                      [NSString stringWithFormat:@"rnssh_%@.key", key]];
                NSString *pubPath  = publicKey.length
                    ? [tmpDir stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"rnssh_%@.pub", key]]
                    : nil;

                [privateKey writeToFile:privPath
                             atomically:YES
                               encoding:NSUTF8StringEncoding
                                  error:&fileError];

                if (fileError) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        callback(@[@{@"message": @"Failed to write private key"}]);
                    });
                    return;
                }

                if (pubPath) {
                    [publicKey writeToFile:pubPath
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:nil];
                }

                authenticated =
                [session authenticateByPublicKey:pubPath
                                       privateKey:privPath
                                      andPassword:passphrase];
            }

            if (!authenticated || !session.authorized) {
                [session disconnect];
                dispatch_async(dispatch_get_main_queue(), ^{
                    callback(@[@{@"message": @"Authentication failed"}]);
                });
                return;
            }

            // ---------------- SUCCESS ----------------
            SSHClient *client = [SSHClient new];
            client.session = session;
            client.key = key;
            client.delegate = self;

            self.clientPool[key] = client;

            dispatch_async(dispatch_get_main_queue(), ^{
                callback(@[[NSNull null]]);
            });

        } @catch (NSException *exception) {
            // Catch any unexpected errors
            dispatch_async(dispatch_get_main_queue(), ^{
                callback(@[@{@"message": exception.reason ?: @"Unknown error"}]);
            });
        }
    });
}



#pragma mark - EXECUTE

RCT_EXPORT_METHOD(execute:(NSString *)command
                  withKey:(NSString *)key
                  withCallback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(self.methodQueue, ^{
        SSHClient *client = [self clientForKey:key];
        if (!client || !client.session || !client.session.connected) {
            callback(@[@{@"message": @"SSH client not connected"}]);
            return;
        }

        NSError *error = nil;

        // Wrap command to capture stderr + exit code
        NSString *wrappedCommand =
        [NSString stringWithFormat:
         @"sh -c '%@ 2>&1; echo \"\\n__EXIT_CODE:$?\"'",
         command];

        NSString *output =
        [client.session.channel execute:wrappedCommand
                                  error:&error
                                timeout:@10];

        // SSH-level error (network, auth, etc.)
        if (error) {
            callback(@[@{
                @"message": error.localizedDescription ?: @"SSH execution failed"
            }]);
            return;
        }

        if (!output.length) {
            callback(@[@{@"message": @"Command produced no output"}]);
            return;
        }

        // Parse exit code
        NSRange exitRange = [output rangeOfString:@"__EXIT_CODE:"];
        NSInteger exitCode = 0;

        if (exitRange.location != NSNotFound) {
            NSString *exitPart = [output substringFromIndex:exitRange.location];
            exitCode = [[exitPart stringByReplacingOccurrencesOfString:@"__EXIT_CODE:"
                                                            withString:@""]
                        integerValue];

            // Remove exit code from output
            output = [output substringToIndex:exitRange.location];
            output = [output stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }

        // Command-level error
        if (exitCode != 0) {
            callback(@[@{
                @"message": output.length ? output : @"Command failed",
                @"code": @(exitCode)
            }]);
            return;
        }

        // Success
        callback(@[[NSNull null], output ?: @""]);
    });
}


#pragma mark - SHELL (PTY)
RCT_EXPORT_METHOD(startShell:(NSString *)key
                  ptyType:(NSString *)ptyType
                  withCallback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(self.methodQueue, ^{
        SSHClient *client = [self clientForKey:key];
        if (!client) {
            callback(@[@{@"message": @"Client not found"}]);
            return;
        }

        NMSSHChannel *channel = client.session.channel;
        channel.delegate = client;

        NSError *error = nil;
        BOOL ok = [channel startShell:&error];

        if (!ok || error) {
            callback(@[@{@"message": error.localizedDescription ?: @"Failed to start shell"}]);
        } else {
            callback(@[[NSNull null]]);
        }
    });
}


RCT_EXPORT_METHOD(writeToShell:(NSString *)key
                  command:(NSString *)command
                  withCallback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(self.methodQueue, ^{
        SSHClient *client = [self clientForKey:key];
        if (!client || !client.session.channel) {
            callback(@[@{@"message": @"Shell not active"}]);
            return;
        }

        NSError *error = nil;
        [client.session.channel write:command error:&error];

        if (error) {
            callback(@[@{@"message": error.localizedDescription}]);
        } else {
            callback(@[[NSNull null]]);
        }
    });
}


#pragma mark - SFTP

RCT_EXPORT_METHOD(connectSFTP:(NSString *)key
                  withCallback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(self.methodQueue, ^{
        SSHClient *client = [self clientForKey:key];
        if (!client) {
            callback(@[@{@"message": @"Client not found"}]);
            return;
        }

        client.sftp = [[NMSFTP alloc] initWithSession:client.session];
        BOOL ok = [client.sftp connect];

        ok ? callback(@[[NSNull null]])
           : callback(@[@{@"message": @"SFTP connection failed"}]);
    });
}

#pragma mark - Recursive Upload / Download

- (BOOL)uploadPath:(NSString *)local
            remote:(NSString *)remote
            client:(SSHClient *)client
             error:(NSError **)outError
{
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;

    if (![fm fileExistsAtPath:local isDirectory:&isDir]) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"RNSSHClient"
                                            code:1001
                                        userInfo:@{
                NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Local path not found: %@", local]
            }];
        }
        return NO;
    }

    if (!isDir) {
        NSData *data = [fm contentsAtPath:local];
        if (!data) {
            if (outError) {
                *outError = [NSError errorWithDomain:@"RNSSHClient"
                                                code:1002
                                            userInfo:@{
                    NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Failed to read local file: %@", local]
                }];
            }
            return NO;
        }

        NSUInteger total = data.length;
        NSUInteger sent = 0;
        NSUInteger chunk = 32768;

        while (sent < total) {
            sent += MIN(chunk, total - sent);
            float progress = ((float)sent / (float)total) * 100.0f;
            [self uploadProgressEvent:progress withKey:client.key];
        }

        BOOL ok = [client.sftp writeContents:data toFileAtPath:remote];
        if (!ok && outError) {
            *outError = [NSError errorWithDomain:@"RNSSHClient"
                                            code:1003
                                        userInfo:@{
                NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Remote write failed: %@", remote]
            }];
        }
        return ok;
    }

    [client.sftp createDirectoryAtPath:remote];

    NSArray *items = [fm contentsOfDirectoryAtPath:local error:outError];
    if (!items) return NO;

    for (NSString *item in items) {
        if (![self uploadPath:
              [local stringByAppendingPathComponent:item]
                         remote:[remote stringByAppendingPathComponent:item]
                         client:client
                          error:outError]) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)downloadPath:(NSString *)remote
               local:(NSString *)local
              client:(SSHClient *)client
               error:(NSError **)outError
{
    NMSFTPFile *info = [client.sftp infoForFileAtPath:remote];
    if (!info) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"RNSSHClient"
                                            code:2001
                                        userInfo:@{
                NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Remote path not found: %@", remote]
            }];
        }
        return NO;
    }

    NSFileManager *fm = NSFileManager.defaultManager;

    if (info.isDirectory) {
        [fm createDirectoryAtPath:local
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

        NSArray<NMSFTPFile *> *files =
        [client.sftp contentsOfDirectoryAtPath:remote];
        if (!files) return NO;

        for (NMSFTPFile *file in files) {
            if (![self downloadPath:
                  [remote stringByAppendingPathComponent:file.filename]
                             local:[local stringByAppendingPathComponent:file.filename]
                            client:client
                             error:outError]) {
                return NO;
            }
        }
        return YES;
    }

    NSData *data = [client.sftp contentsAtPath:remote];
    if (!data) return NO;

    [fm createFileAtPath:local contents:data attributes:nil];
    [self downloadProgressEvent:100.0f withKey:client.key];
    return YES;
}

#pragma mark - SFTP LIST / STAT

RCT_EXPORT_METHOD(sftpList:(NSString *)remotePath
                  withKey:(NSString *)key
                  withCallback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(self.methodQueue, ^{
        SSHClient *client = [self clientForKey:key];
        if (!client || !client.sftp) {
            callback(@[@{@"message": @"SFTP not connected"}]);
            return;
        }

        NSArray<NMSFTPFile *> *files =
        [client.sftp contentsOfDirectoryAtPath:remotePath];

        NSMutableArray *result = [NSMutableArray array];
        for (NMSFTPFile *file in files) {
            [result addObject:@{
                @"filename": file.filename ?: @"",
                @"permissions": file.permissions ?: @(0),
                @"fileSize": file.fileSize ?: @(0),
                @"isDirectory": @(file.isDirectory)
            }];
        }

        callback(@[[NSNull null], result]);
    });
}

RCT_EXPORT_METHOD(sftpUpload:(NSString *)local
                  remote:(NSString *)remote
                  withKey:(NSString *)key
                  withCallback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(self.methodQueue, ^{
        SSHClient *client = [self clientForKey:key];
        if (!client || !client.sftp) {
            callback(@[@{@"message": @"SFTP not connected"}]);
            return;
        }

        NSError *error = nil;
        BOOL ok = [self uploadPath:local remote:remote client:client error:&error];

        if (!ok) {
            callback(@[@{@"message": error.localizedDescription ?: @"Upload failed"}]);
        } else {
            callback(@[[NSNull null]]);
        }
    });
}

RCT_EXPORT_METHOD(sftpDownload:(NSString *)remote
                  local:(NSString *)local
                  withKey:(NSString *)key
                  withCallback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(self.methodQueue, ^{
        SSHClient *client = [self clientForKey:key];
        if (!client || !client.sftp) {
            callback(@[@{@"message": @"SFTP not connected"}]);
            return;
        }

        NSError *error = nil;
        BOOL ok = [self downloadPath:remote local:local client:client error:&error];

        if (!ok) {
            callback(@[@{@"message": error.localizedDescription ?: @"Download failed"}]);
        } else {
            callback(@[[NSNull null]]);
        }
    });
}



RCT_EXPORT_METHOD(sftpStat:(NSString *)remotePath
                  withKey:(NSString *)key
                  withCallback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(self.methodQueue, ^{
        SSHClient *client = [self clientForKey:key];
        if (!client || !client.sftp) {
            callback(@[@{@"message": @"SFTP not connected"}]);
            return;
        }

        NMSFTPFile *file = [client.sftp infoForFileAtPath:remotePath];
        if (!file) {
            callback(@[@{@"message": @"File not found"}]);
            return;
        }

        callback(@[[NSNull null], @{
            @"filename": file.filename ?: @"",
            @"permissions": file.permissions ?: @(0),
            @"fileSize": file.fileSize ?: @(0),
            @"isDirectory": @(file.isDirectory)
        }]);
    });
}

#pragma mark - DISCONNECT

RCT_EXPORT_METHOD(disconnect:(NSString *)key
                  withCallback:(RCTResponseSenderBlock)callback)
{
    dispatch_async(self.methodQueue, ^{
        @try {
            SSHClient *client = self.clientPool[key];
            if (client) {
                if (client.session.channel) {
                    [client.session.channel closeShell];
                }
                [client.session disconnect];
                [self.clientPool removeObjectForKey:key];
                callback(@[[NSNull null]]);
            }else{
                callback(@[@{@"message": @"Client not found"}]);
                return;
            }
        } @catch (NSException *exception) {
            callback(@[@{@"message": exception.description}]);
        }
    });
}


@end
