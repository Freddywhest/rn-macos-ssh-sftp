import { NativeModules, NativeEventEmitter } from 'react-native';

const { RNSSHClient } = NativeModules;

// --- Typed Native Module ---
interface RNSSHClientType {
  connectToHost(
    host: string,
    port: number,
    username: string,
    passwordOrKey: string | { privateKey: string; publicKey?: string; passphrase?: string },
    timeout: number,
    key: string,
    callback: (error: unknown) => void
  ): void;

  execute(command: string, key: string, callback: (error: unknown, result?: string) => void): void;

  startShell(key: string, ptyType: string, callback: (error: unknown) => void): void;

  writeToShell(key: string, command: string, callback: (error: unknown) => void): void;

  disconnect(key: string): void;

  connectSFTP(key: string, callback: (error: unknown) => void): void;

  sftpUpload(local: string, remote: string, key: string, callback: (error: unknown) => void): void;

  sftpList(remotePath: string, key: string, callback: (error: unknown, result?: string[]) => void): void;

  sftpStat(remotePath: string, key: string, callback: (error: unknown, result?: unknown) => void): void;

  sftpDownload(remote: string, local: string, key: string, callback: (error: unknown) => void): void;
}

// Cast the native module
const RNSSHClientTyped = RNSSHClient as RNSSHClientType;

// --- Events ---
const RNSSHClientEmitter = new NativeEventEmitter(RNSSHClient);

const EVENT_SHELL = 'Shell';
const EVENT_UPLOAD_PROGRESS = 'UploadProgress';
const EVENT_DOWNLOAD_PROGRESS = 'DownloadProgress';

type CBError = unknown;

export type Callback<T = unknown> = (error: CBError, result?: T) => void;
export type EventHandler<T = unknown> = (data: T) => void;

export enum PtyType {
  VANILLA = 'vanilla',
  VT100 = 'vt100',
  VT102 = 'vt102',
  VT220 = 'vt220',
  ANSI = 'ansi',
  XTERM = 'xterm',
}

export interface KeyPair {
  privateKey: string;
  publicKey?: string;
  passphrase?: string;
}

export type PasswordOrKey = string | KeyPair;

// --- SSH Client Class ---
export default class SSHClient {
  private _key: string;
  private _activeShell = false;
  private _activeSFTP = false;
  private _handlers: Record<string, EventHandler> = {};

  constructor(
    private host: string,
    private port: number,
    private username: string,
    private passwordOrKey?: PasswordOrKey,
    private timeout: number = 15 // seconds
  ) {
    this._key = Math.random().toString(36).substring(2, 10);
  }

  /** Connect to the SSH server. Returns a Promise that resolves if successful, rejects if error */
  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.passwordOrKey) return reject(new Error('Password or Key must be provided'));
      RNSSHClientTyped.connectToHost(
        this.host,
        this.port,
        this.username,
        this.passwordOrKey,
        this.timeout,
        this._key,
        (err: CBError) => {
          if (err) reject(err);
          else resolve();
        }
      );
    });
  }

  on(eventName: 'shell' | 'upload' | 'download', handler: EventHandler) {
    this._handlers[eventName] = handler;

    const nativeEvent =
      eventName === 'shell'
        ? EVENT_SHELL
        : eventName === 'upload'
          ? EVENT_UPLOAD_PROGRESS
          : EVENT_DOWNLOAD_PROGRESS;

    RNSSHClientEmitter.addListener(nativeEvent, (payload: { key: string; data?: string; progress?: number }) => {
      if (payload.key === this._key) {
        handler(payload.data ?? payload.progress);
      }
    });
  }

  execute(command: string): Promise<string> {
    return new Promise((resolve, reject) => {
      RNSSHClientTyped.execute(command, this._key, (error: CBError, result?: string) => {
        if (error) return reject(error);
        resolve(result ?? '');
      });
    });
  }

  startShell(pty: PtyType = PtyType.VANILLA): Promise<void> {
    if (this._activeShell) return Promise.resolve();

    return new Promise((resolve, reject) => {
      RNSSHClientTyped.startShell(this._key, pty, (err: CBError) => {
        if (err) return reject(err);
        this._activeShell = true;
        resolve();
      });
    });
  }

  writeToShell(command: string): Promise<void> {
    if (!this._activeShell) throw new Error('Shell not active');

    return new Promise((resolve, reject) => {
      RNSSHClientTyped.writeToShell(this._key, command, (err: CBError) => {
        if (err) return reject(err);
        resolve();
      });
    });
  }

  closeShell(): void {
    if (!this._activeShell) return;
    RNSSHClientTyped.disconnect(this._key); // native closes session
    this._activeShell = false;
  }

  connectSFTP(): Promise<void> {
    if (this._activeSFTP) return Promise.resolve();

    return new Promise((resolve, reject) => {
      RNSSHClientTyped.connectSFTP(this._key, (err: CBError) => {
        if (err) return reject(err);
        this._activeSFTP = true;
        resolve();
      });
    });
  }

  sftpUpload(local: string, remote: string): Promise<void> {
    return this.connectSFTP().then(
      () =>
        new Promise((resolve, reject) => {
          RNSSHClientTyped.sftpUpload(local, remote, this._key, (err: CBError) => {
            if (err) return reject(err);
            resolve();
          });
        })
    );
  }

  sftpDownload(remote: string, local: string): Promise<void> {
    return this.connectSFTP().then(
      () =>
        new Promise((resolve, reject) => {
          RNSSHClientTyped.sftpDownload(remote, local, this._key, (err: CBError) => {
            if (err) return reject(err);
            resolve();
          });
        })
    );
  }

  list(remotePath: string): Promise<string[]> {
    return new Promise((resolve, reject) => {
      RNSSHClientTyped.sftpList(remotePath, this._key, (err: CBError, result?: string[]) => {
        if (err) return reject(err);
        resolve(result ?? []);
      });
    });
  }

  stat(remotePath: string): Promise<{
    filename: string;
    longName: string;
    permissions: number;
    fileSize: number;
    isDirectory: boolean;
  }> {
    return new Promise((resolve, reject) => {
      RNSSHClientTyped.sftpStat(remotePath, this._key, (err: CBError, result?: unknown) => {
        if (err) return reject(err);
        resolve(result as {
          filename: string;
          longName: string;
          permissions: number;
          fileSize: number;
          isDirectory: boolean;
        });
      });
    });
  }


  disconnect(): void {
    if (this._activeShell) this.closeShell();
    if (this._activeSFTP) this._activeSFTP = false;
    RNSSHClientTyped.disconnect(this._key);
  }
}
