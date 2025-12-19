#import "NMSSH/NMSSH.h"
#import "NMSSH/NMSFTP.h"

@protocol SSHClientDelegate <NSObject>
- (void)shellEvent:(NSString *)event withKey:(NSString *)key;
- (void)downloadProgressEvent:(float)progress withKey:(NSString *)key;
- (void)uploadProgressEvent:(float)progress withKey:(NSString *)key;
@end

@interface SSHClient : NSObject <NMSSHChannelDelegate>

@property(nonatomic, strong) NMSSHSession *session;
@property(nonatomic, strong) NMSFTP *sftp;
@property(nonatomic, strong) NSString *key;
@property(nonatomic, weak) id<SSHClientDelegate> delegate;

- (BOOL)connectSFTP;
- (NSDictionary *)stat:(NSString *)path;
- (BOOL)chmod:(NSString *)path mode:(NSNumber *)mode;
- (NSString *)readFile:(NSString *)path;
- (BOOL)writeFile:(NSString *)path content:(NSString *)content;

/* Interactive shell */
- (void)startShellWithPty:(NSString *)pty;
- (void)writeToShell:(NSString *)command;

/* Recursive upload/download with progress */
- (BOOL)uploadRecursive:(NSString *)localPath
                     to:(NSString *)remotePath
               progress:(void (^)(float percent))progress;

- (BOOL)downloadRecursive:(NSString *)remotePath
                       to:(NSString *)localPath
                 progress:(void (^)(float percent))progress;

/* Cancel operations */
- (void)cancelUpload;
- (void)cancelDownload;

@end
