#import "SSHClient.h"

@implementation SSHClient

#pragma mark - SFTP Connect
- (BOOL)connectSFTP {
    if (!self.sftp) {
        self.sftp = [[NMSFTP alloc] initWithSession:self.session];
        return [self.sftp connect];
    }
    return YES;
}

#pragma mark - Directory Listing
- (NSArray *)list:(NSString *)path {
    NSArray *files = [self.sftp contentsOfDirectoryAtPath:path];
    NSMutableArray *out = [NSMutableArray new];

    for (NMSFTPFile *f in files) {
        [out addObject:@{
            @"filename": f.filename ?: @"",
            @"isDirectory": @(f.isDirectory),
            @"fileSize": f.fileSize ?: @0,
            @"permissions": f.permissions ?: @"",
            @"lastModified": @(f.modificationDate.timeIntervalSince1970)
        }];
    }
    return out;
}

#pragma mark - File Stat
- (NSDictionary *)stat:(NSString *)path {
    NMSFTPFile *f = [self.sftp infoForFileAtPath:path];
    if (!f) return nil;

    return @{
        @"filename": f.filename ?: @"",
        @"isDirectory": @(f.isDirectory),
        @"fileSize": f.fileSize ?: @0,
        @"permissions": f.permissions ?: @"",
        @"lastModified": @(f.modificationDate.timeIntervalSince1970)
    };
}

#pragma mark - Chmod (macOS: fallback via SSH)
- (BOOL)chmod:(NSString *)path mode:(NSNumber *)mode {
    NSString *command = [NSString stringWithFormat:@"chmod %o %@", mode.intValue, path];
    NSError *error = nil;
    [self.session.channel execute:command error:&error];
    return (error == nil);
}

#pragma mark - Read/Write File
- (NSString *)readFile:(NSString *)path {
    NSData *data = [self.sftp contentsAtPath:path];
    if (!data) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (BOOL)writeFile:(NSString *)path content:(NSString *)content {
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    return [self.sftp writeContents:data toFileAtPath:path];
}

#pragma mark - PTY Shell
- (void)startShellWithPty:(NSString *)pty {
    NSError *error = nil;
    [self.session.channel startShell:&error];
}

- (void)writeToShell:(NSString *)command {
    NSError *error = nil;
    [self.session.channel write:command error:&error];
}

#pragma mark - Upload/Download Recursive (macOS, float progress)
- (BOOL)uploadRecursive:(NSString *)localPath
                     to:(NSString *)remotePath
               progress:(void (^)(float))progress
{
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    [fm fileExistsAtPath:localPath isDirectory:&isDir];

    if (!isDir) {
        NSData *data = [fm contentsAtPath:localPath];
        BOOL ok = [self.sftp writeContents:data toFileAtPath:remotePath];
        if (progress) progress(1.0);
        return ok;
    }

    [self.sftp createDirectoryAtPath:remotePath];
    NSArray *items = [fm contentsOfDirectoryAtPath:localPath error:nil];
    for (NSString *item in items) {
        NSString *l = [localPath stringByAppendingPathComponent:item];
        NSString *r = [remotePath stringByAppendingPathComponent:item];
        if (![self uploadRecursive:l to:r progress:progress]) return NO;
    }
    return YES;
}

- (BOOL)downloadRecursive:(NSString *)remotePath
                       to:(NSString *)localPath
                 progress:(void (^)(float))progress
{
    NMSFTPFile *file = [self.sftp infoForFileAtPath:remotePath];
    if (!file.isDirectory) {
        NSData *data = [self.sftp contentsAtPath:remotePath];
        [data writeToFile:localPath atomically:YES];
        if (progress) progress(1.0);
        return YES;
    }

    [[NSFileManager defaultManager] createDirectoryAtPath:localPath withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray *files = [self.sftp contentsOfDirectoryAtPath:remotePath];
    for (NMSFTPFile *f in files) {
        NSString *r = [remotePath stringByAppendingPathComponent:f.filename];
        NSString *l = [localPath stringByAppendingPathComponent:f.filename];
        if (![self downloadRecursive:r to:l progress:progress]) return NO;
    }
    return YES;
}

#pragma mark - Cancel Upload/Download
- (void)cancelUpload {}
- (void)cancelDownload {}

@end
