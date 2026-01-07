import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:rtmp/rtmp.dart';
import 'mp4_parser.dart';

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
    final videoTrack = await parser.findH264Track();
    final audioTrack = await parser.findAACTrack();

    if (videoTrack == null) {
      print('Error: No H.264 track found in MP4 file.');
      await raf.close();
      return;
    }

    print('Connecting to $url...');
    await client
        .connect(url, ignoreCertificateErrors: true)
        .timeout(const Duration(seconds: 10));

    print('Creating stream...');
    final stream = await client.createStream();

    // Extract stream key from URL (simplified)
    final uri = Uri.parse(url);
    final streamKey = uri.pathSegments.last;

    print('Publishing with key: $streamKey...');
    await stream.publish(streamKey);

    // 1. Send Sequence Headers
    print('Sending sequence headers...');
    stream.sendH264SequenceHeader(videoTrack.avcC);
    if (audioTrack != null) {
      try {
        stream.sendAACSequenceHeader(audioTrack.aacConfig);
      } catch (e) {
        print('Warning: Could not extract AAC config: $e');
      }
    }

    // 2. Prepare Samples
    print('Extracting samples and durations...');
    final videoSamples = await videoTrack.getSamples();
    final videoDurations = await videoTrack.getSampleDurations();
    final videoTimescale = videoTrack.timescale;

    final audioSamples = audioTrack != null
        ? await audioTrack.getSamples()
        : <Uint8List>[];
    final audioDurations = audioTrack != null
        ? await audioTrack.getSampleDurations()
        : <int>[];
    final audioTimescale = audioTrack != null ? audioTrack.timescale : 1;

    print(
      'Found ${videoSamples.length} video samples and ${audioSamples.length} audio samples.',
    );

    // 3. Send Metadata
    stream.sendMetadata({
      'videocodecid': 7.0, // H.264
      'width': 1280.0,
      'height': 720.0,
      'framerate': 30.0,
      if (audioTrack != null) 'audiocodecid': 10.0, // AAC
    });

    // 4. Interleave and Stream
    final allSamples = <_Sample>[];

    int videoTs = 0;
    for (var i = 0; i < videoSamples.length; i++) {
      allSamples.add(
        _Sample(videoSamples[i], (videoTs * 1000) ~/ videoTimescale, true),
      );
      videoTs += (i < videoDurations.length) ? videoDurations[i] : 0;
    }

    if (audioTrack != null) {
      int audioTs = 0;
      for (var i = 0; i < audioSamples.length; i++) {
        allSamples.add(
          _Sample(audioSamples[i], (audioTs * 1000) ~/ audioTimescale, false),
        );
        audioTs += (i < audioDurations.length) ? audioDurations[i] : 0;
      }
    }

    allSamples.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    print('Starting interleaved stream with accurate timestamps...');
    final stopwatch = Stopwatch()..start();
    int lastTimestamp = 0;
    try {
      for (var sample in allSamples) {
        // Wait until it's time to send this sample
        final wallClockTime = stopwatch.elapsedMilliseconds;
        final waitTime = sample.timestamp - wallClockTime;
        if (waitTime > 0) {
          await Future.delayed(Duration(milliseconds: waitTime));
        }

        if (sample.isVideo) {
          final naluType = sample.data[4] & 0x1F;
          final isKey = naluType == 5 || naluType == 7 || naluType == 8;
          stream.sendH264Sample(
            sample.data,
            sample.timestamp,
            isKeyframe: isKey,
          );
        } else {
          stream.sendAACSample(sample.data, sample.timestamp);
        }

        if (sample.isVideo &&
            lastTimestamp ~/ 1000 != sample.timestamp ~/ 1000) {
          print('Streaming... (timestamp: ${sample.timestamp} ms)');
        }

        lastTimestamp = sample.timestamp;
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

class _Sample {
  final Uint8List data;
  final int timestamp;
  final bool isVideo;

  _Sample(this.data, this.timestamp, this.isVideo);
}
