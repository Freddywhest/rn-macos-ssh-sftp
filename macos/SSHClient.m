#import "SSHClient.h"

@implementation SSHClient

#pragma mark - Shell

- (void)startShell:(NSString *)ptyType error:(NSError **)error
{
    NMSSHChannel *channel = self._session.channel;
    channel.delegate = self;
    channel.requestPty = YES;

    channel.ptyTerminalType = NMSSHChannelPtyTerminalXterm;

    [channel startShell:error];
}

#pragma mark - SFTP Download

- (void)sftpDownload:(NSString *)path
              toPath:(NSString *)filePath
               error:(NSError **)error
{
    self._sftpSession = [[NMSFTP alloc] initWithSession:self._session];
    [self._sftpSession connect];

    self._downloadContinue = YES;
    __block int lastProgress = 0;

    NSData *data =
    [self._sftpSession contentsAtPath:path
                             progress:^BOOL(NSUInteger bytes, NSUInteger fileSize)
    {
        int percent = (int)((bytes * 100) / fileSize);

        if (percent >= lastProgress + 5) {
            lastProgress = percent;
            if ([self.delegate respondsToSelector:@selector(downloadProgressEvent:withKey:)]) {
                [self.delegate downloadProgressEvent:percent withKey:self._key];
            }
        }

        return self._downloadContinue;
    }];

    if (data) {
        [data writeToFile:filePath options:NSDataWritingAtomic error:error];
    }
}

#pragma mark - SFTP Upload

- (BOOL)sftpUpload:(NSString *)filePath toPath:(NSString *)path
{
    self._sftpSession = [[NMSFTP alloc] initWithSession:self._session];
    [self._sftpSession connect];

    self._uploadContinue = YES;
    __block int lastProgress = 0;

    NSString *remotePath =
        [path stringByAppendingPathComponent:[filePath lastPathComponent]];

    long long fileSize =
        [[[NSFileManager defaultManager]
          attributesOfItemAtPath:filePath
          error:nil][NSFileSize] longLongValue];

    BOOL result =
    [self._sftpSession writeFileAtPath:filePath
                        toFileAtPath:remotePath
                             progress:^BOOL(NSUInteger bytes)
    {
        int percent = (int)((bytes * 100) / fileSize);

        if (percent >= lastProgress + 5) {
            lastProgress = percent;
            if ([self.delegate respondsToSelector:@selector(uploadProgressEvent:withKey:)]) {
                [self.delegate uploadProgressEvent:percent withKey:self._key];
            }
        }

        return self._uploadContinue;
    }];

    return result;
}

#pragma mark - NMSSHChannelDelegate

- (void)channel:(NMSSHChannel *)channel didReadData:(NSString *)message
{
    if ([self.delegate respondsToSelector:@selector(shellEvent:withKey:)]) {
        [self.delegate shellEvent:message withKey:self._key];
    }
}

- (void)channel:(NMSSHChannel *)channel didReadError:(NSString *)error
{
    if ([self.delegate respondsToSelector:@selector(shellEvent:withKey:)]) {
        [self.delegate shellEvent:error withKey:self._key];
    }
}

@end
