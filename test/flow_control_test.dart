import 'dart:typed_data';

import 'package:rtmp/src/chunk/chunk_handler.dart';
import 'package:rtmp/src/chunk/models.dart';
import 'package:rtmp/src/flow_control.dart';
import 'package:rtmp/src/protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Flow control events', () {
    test('Acknowledgement emits flow control event', () {
      final events = <RtmpFlowControlEvent>[];
      final protocol = RtmpProtocol(
        chunkHandler: ChunkHandler(),
        onSend: (_) {},
        onFlowControl: events.add,
      );

      final payload = ByteData(4)..setUint32(0, 1024, Endian.big);
      final message = RtmpMessage(
        chunkStreamId: 2,
        type: RtmpMessageType.acknowledgement,
        messageStreamId: 0,
        timestamp: 0,
        payload: payload.buffer.asUint8List(),
      );

      protocol.handleMessage(message);

      expect(events, hasLength(1));
      final event = events.first as RtmpAcknowledgement;
      expect(event.bytesAcknowledged, 1024);
    });

    test('Window acknowledgement size emits flow control event', () {
      final events = <RtmpFlowControlEvent>[];
      final protocol = RtmpProtocol(
        chunkHandler: ChunkHandler(),
        onSend: (_) {},
        onFlowControl: events.add,
      );

      final payload = ByteData(4)..setUint32(0, 4096, Endian.big);
      final message = RtmpMessage(
        chunkStreamId: 2,
        type: RtmpMessageType.windowAcknowledgementSize,
        messageStreamId: 0,
        timestamp: 0,
        payload: payload.buffer.asUint8List(),
      );

      protocol.handleMessage(message);

      expect(events, hasLength(1));
      final event = events.first as RtmpWindowAcknowledgementSize;
      expect(event.windowSize, 4096);
    });
  });
}
