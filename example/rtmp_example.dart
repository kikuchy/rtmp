import 'dart:async';
import 'dart:io';

import 'package:rtmp/rtmp.dart';
import 'package:rtmp/src/utils/mp4_parser.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print(
      'Usage: dart example/rtmp_example.dart <path_to_mp4_file> [rtmp_url]',
    );
    return;
  }

  final filePath = args[0];
  final url = args.length > 1 ? args[1] : 'rtmp://127.0.0.1:1935/live/test';

  final file = File(filePath);
  if (!await file.exists()) {
    print('Error: File not found: $filePath');
    return;
  }

  final client = RtmpClient();

  try {
    print('Opening file: $filePath');
    final raf = await file.open();
    final parser = Mp4Parser(raf);

    print('Parsing MP4...');
    final track = await parser.findH264Track();
    if (track == null) {
      print('Error: No H.264 track found in MP4 file.');
      await raf.close();
      return;
    }

    print('Connecting to $url...');
    await client.connect(url).timeout(const Duration(seconds: 10));

    print('Creating stream...');
    final stream = await client.createStream();

    // Extract stream key from URL (simplified)
    final uri = Uri.parse(url);
    final streamKey = uri.pathSegments.last;

    print('Publishing with key: $streamKey...');
    await stream.publish(streamKey);

    // 1. Send Sequence Header (SPS/PPS)
    print('Sending AVC sequence header...');
    stream.sendH264SequenceHeader(track.avcC);

    // 2. Send Samples
    print('Extracting samples...');
    final samples = await track.getSamples();
    print('Found ${samples.length} samples. Starting stream...');

    // 3. Send Metadata
    stream.sendMetadata({
      'videocodecid': 7.0, // H.264
      'width': 1280.0,
      'height': 720.0,
      'framerate': 30.0,
    });

    int timestamp = 0;
    const frameInterval = 33; // ~30 fps

    try {
      for (var i = 0; i < samples.length; i++) {
        final sample = samples[i];

        // NALU type is at sample[4] in AVCC format (4 bytes length + 1 byte type)
        final naluType = sample[4] & 0x1F;
        final isKey = naluType == 5 || naluType == 7 || naluType == 8;

        stream.sendH264Sample(sample, timestamp, isKeyframe: isKey);

        if (i % 30 == 0) {
          print('Sent $i samples... (timestamp: $timestamp ms)');
        }

        timestamp += frameInterval;
        await Future.delayed(const Duration(milliseconds: frameInterval));
      }
    } on SocketException catch (e) {
      print('Socket error during streaming: ${e.message}');
    }

    print('Finished streaming all samples.');
    await raf.close();
    await client.close();
  } catch (e, stack) {
    print('Error: $e');
    print(stack);
  }
}
