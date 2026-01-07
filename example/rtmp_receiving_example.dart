import 'dart:io';
import 'package:rtmp/rtmp.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart example/rtmp_receiving_example.dart <rtmp_url>');
    return;
  }

  final url = args[0];
  final client = RtmpClient();

  try {
    print('Connecting to $url...');
    await client.connect(url);
    print('Connected.');

    print('Creating stream...');
    final stream = await client.createStream();
    print('Stream created (ID: ${stream.streamId}).');

    // Extract stream key from URL or use a default
    final uri = Uri.parse(url);
    final streamKey = uri.pathSegments.length > 1
        ? uri.pathSegments[1]
        : 'test';

    print('Playing stream: $streamKey...');
    await stream.play(streamKey);

    int videoPackets = 0;
    int audioPackets = 0;
    int totalVideoBytes = 0;
    int totalAudioBytes = 0;

    stream.metadataStream.listen((metadata) {
      print('Received Metadata: $metadata');
    });

    stream.videoStream.listen((packet) {
      videoPackets++;
      totalVideoBytes += packet.data.length;
      if (videoPackets % 100 == 0) {
        print(
          'Video: $videoPackets packets, $totalVideoBytes bytes received. Last TS: ${packet.timestamp}',
        );
      }
    });

    stream.audioStream.listen((packet) {
      audioPackets++;
      totalAudioBytes += packet.data.length;
      if (audioPackets % 100 == 0) {
        print(
          'Audio: $audioPackets packets, $totalAudioBytes bytes received. Last TS: ${packet.timestamp}',
        );
      }
    });

    // Keep the example running
    await ProcessSignal.sigint.watch().first;
    print('\nStopping...');
    await stream.close();
    await client.close();
  } catch (e) {
    print('Error: $e');
  }
}
