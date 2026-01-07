import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:rtmp/src/chunk/chunk_handler.dart';
import 'package:rtmp/src/chunk/models.dart';

void main() {
  group('Chunking', () {
    test('Single Chunk Message', () {
      final handler = ChunkHandler();
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final msg = RtmpMessage(
        chunkStreamId: 3,
        type: RtmpMessageType.audioMessage,
        messageStreamId: 1,
        timestamp: 100,
        payload: payload,
      );

      final chunks = handler.encodeMessage(msg);
      expect(chunks.length, 1);

      final decoded = handler.handleData(chunks[0]);
      expect(decoded.length, 1);
      expect(decoded[0].payload, equals(payload));
      expect(decoded[0].timestamp, 100);
      expect(decoded[0].type, RtmpMessageType.audioMessage);
    });

    test('Multi-Chunk Message', () {
      final handler = ChunkHandler();
      handler.outChunkSize = 128;
      handler.inChunkSize = 128;

      final payload = Uint8List(300);
      for (var i = 0; i < 300; i++) {
        payload[i] = i % 256;
      }

      final msg = RtmpMessage(
        chunkStreamId: 4,
        type: RtmpMessageType.videoMessage,
        messageStreamId: 1,
        timestamp: 200,
        payload: payload,
      );

      final chunks = handler.encodeMessage(msg);
      expect(chunks.length, 3); // 128 + 128 + 44

      List<RtmpMessage> decoded = [];
      for (var chunk in chunks) {
        decoded.addAll(handler.handleData(chunk));
      }

      expect(decoded.length, 1);
      expect(decoded[0].payload, equals(payload));
      expect(decoded[0].timestamp, 200);
    });
  });
}
