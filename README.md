# rtmp

A pure Dart library for RTMP (Real-Time Messaging Protocol).

## Features

- **Pure Dart**: Implementation is entirely in Dart, ensuring cross-platform compatibility.
- **Zero Dependencies**: No external package dependencies.
- **Publishing & Receiving**: Supports both publishing to an RTMP server and receiving a stream from one.
- **Cross-Platform**: Works on Flutter, Dart CLI, and any other Dart-supported environment.
- **H.264 & AAC Support**: Basic support for common video and audio codecs.

> [!IMPORTANT]
> This package is an RTMP client. It does **not** include RTMP server functionality.

### Screenshot

YouTube Live from [rtmp_publishing_example.dart](https://github.com/kikuchy/rtmp/blob/main/example/rtmp_publishing_example.dart)

![Screenshot](doc/assets/screenshot.png)

## Getting started

Add `rtmp` to your `pubspec.yaml`:

```yaml
dependencies:
  rtmp: ^0.0.1
```

## Usage

### Publishing a Stream

```dart
import 'package:rtmp/rtmp.dart';

void main() async {
  final client = RtmpClient();
  await client.connect('rtmp://your-server-url/live');
  
  final stream = await client.createStream();
  await stream.publish('stream-key');
  
  // Send data...
  // stream.sendH264Sample(data, timestamp);
  
  await stream.close();
  await client.close();
}
```

### Receiving a Stream

```dart
import 'package:rtmp/rtmp.dart';

void main() async {
  final client = RtmpClient();
  await client.connect('rtmp://your-server-url/live');
  
  final stream = await client.createStream();
  await stream.play('stream-key');
  
  stream.videoStream.listen((packet) {
    print('Received video packet: ${packet.timestamp}');
  });
  
  // Wait or handle signals...
}
```

## Additional information

For more detailed examples, check the `example/` directory in the repository.

- [rtmp_publishing_example.dart](https://github.com/kikuchy/rtmp/blob/main/example/rtmp_publishing_example.dart)
- [rtmp_receiving_example.dart](https://github.com/kikuchy/rtmp/blob/main/example/rtmp_receiving_example.dart)
