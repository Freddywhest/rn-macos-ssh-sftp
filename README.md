# SSH and SFTP client library for React Native

SSH and SFTP client library for React Native on MacOS.

[![Compile package](https://github.com/FreddyWhest/rn-macos-ssh-sftp/actions/workflows/compile.yml/badge.svg)](https://github.com/FreddyWhest/rn-macos-ssh-sftp/actions/workflows/compile.yml) [![Publish package to npmjs.com](https://github.com/FreddyWhest/rn-macos-ssh-sftp/actions/workflows/publish.yml/badge.svg)](https://github.com/FreddyWhest/rn-macos-ssh-sftp/actions/workflows/publish.yml)

## Installation

```bash
npm install rn-macos-ssh-sftp
```

### macOS

Run `pod install` in your `./macos` directory.

```bash
cd macos
pod install
cd -
```

> [!TIP]
> Adding a `postinstall` script to your `package.json` file to run `pod install` after `npm install` is a good idea. The [`pod-install`](https://www.npmjs.com/package/pod-install) package is a good way to do this.
>
> ```json
> {
>   "scripts": {
>     "postinstall": "npx pod-install"
>   }
> }
> ```

#### Having OpenSSL issues on MacOS?

If you are using [Flipper](https://fbflipper.com/) to debug your app, it will already have a copy of OpenSSL included. This can cause issues with the version of OpenSSL that NMSSH uses. You can disable flipper by removing/commenting out the `flipper_configuration => flipper_config,` line in your `Podfile`.

### Android

No additional steps are needed for Android.

### Linking

This project has been updated to use React Native v73 (the latest at the time of writing, Jan 2024) - which means that manual linking is not required.

## Usage

All functions that run asynchronously where we have to wait for a result returns Promises that can reject if an error occurred.

> [!NOTE]
> On macOS, this package currently doesn't support the simulator, you will need to have your app running on a physical device. If you would like to know more about this, see [this issue](https://github.com/FreddyWhest/rn-macos-ssh-sftp/issues/20). I'd welcome a PR to resolve this.

### Create a client using password authentication

```javascript
import SSHClient from 'rn-macos-ssh-sftp';

try{
  // Create SSH client with private keys
   const client = new SSHClient(
      '123.123.123.1', // server/ssh ip/host
      'port',
      'username',
      {
        privateKey,
        passphrase: '1234', // replace with your passphrase
      },
      10, // timeout
    );
  
    // Create SSH client with passowrd
     const client = new SSHClient(
      '123.123.123.1', // server/ssh ip/host
      'port',
      'username',
      'password',
      10, // timeout
    );

    await client.connect();
    console.log('SSH connected successfully...');
}catch(e){
  console.error(error)
}

#### Public key authentication is also supported

```plaintext
{privateKey: '-----BEGIN RSA......'}
{privateKey: '-----BEGIN RSA......', publicKey: 'ssh-rsa AAAAB3NzaC1yc2EA......'}
{privateKey: '-----BEGIN RSA......', publicKey: 'ssh-rsa AAAAB3NzaC1yc2EA......', passphrase: 'Password'}
```

### Close client

```javascript
client.disconnect();
```

### Execute SSH command

```javascript
const command = 'ls -l';
client.execute(command).then((output) => console.warn(output));
```

### Shell

#### Start shell

- Supported ptyType: vanilla, vt100, vt102, vt220, ansi, xterm

```javascript
const ptyType = 'vanilla';
client.startShell(ptyType).then(() => {
  /*...*/
});
```

#### Read from shell

```javascript
client.on('shell', (event) => {
  if (event) console.warn(event);
});
```

#### Write to shell

```javascript
const str = 'ls -l\n';
client.writeToShell(str).then(() => {
  /*...*/
});
```

#### Close shell

```javascript
client.closeShell();
```

### SFTP

#### Connect SFTP

```javascript
client.connectSFTP().then(() => {
  /*...*/
});
```

#### List directory

```javascript
const path = '.';
client.list(path).then((response) => console.warn(response));
```

#### Download file

```javascript
client.sftpDownload('[path-to-remote-file]', '[path-to-local-directory]').then((downloadedFilePath) => {
  console.warn(downloadedFilePath);
});

// Download progress (setup before call)
client.on('download', (event) => {
  console.warn(event);
});

// Cancel download
client.sftpCancelDownload();
```

#### Upload file

```javascript
client.sftpUpload('[path-to-local-file]', '[path-to-remote-directory]').then(() => {
  /*...*/
});

// Upload progress (setup before call)
client.on('upload', (event) => {
  console.warn(event);
});

```

#### Close SFTP

```javascript
client.disconnect();
```

## Example app

You can find a very simple example app for the usage of this library [here]().

## Credits

This package wraps the following libraries, which provide the actual SSH/SFTP functionality:

- [NMSSH](https://github.com/aanah0/NMSSH) for MacOS
- [JSch](http://www.jcraft.com/jsch/) for Android ([from Matthias Wiedemann fork](https://github.com/mwiede/jsch))

This package is a fork of Emmanuel Natividad's [react-native-ssh-sftp](https://github.com/enatividad/react-native-ssh-sftp) package. The fork chain from there is as follows:

1. [Gabriel Paul "Cley Faye" Risterucci](https://github.com/KeeeX/react-native-ssh-sftp)
1. [Bishoy Mikhael](https://github.com/MrBmikhael/react-native-ssh-sftp)
1. [Qian Sha](https://github.com/shaqian/react-native-ssh-sftp)
