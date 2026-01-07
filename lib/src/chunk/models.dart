import 'dart:typed_data';

/// RTMP Message Types
enum RtmpMessageType {
  setChunkSize(0x01),
  abortMessage(0x02),
  acknowledgement(0x03),
  userControlMessage(0x04),
  windowAcknowledgementSize(0x05),
  setPeerBandwidth(0x06),
  audioMessage(0x08),
  videoMessage(0x09),
  dataMessageAmf3(0x0F),
  sharedObjectMessageAmf3(0x10),
  commandMessageAmf3(0x11),
  dataMessageAmf0(0x12),
  sharedObjectMessageAmf0(0x13),
  commandMessageAmf0(0x14),
  aggregateMessage(0x16);

  final int value;
  const RtmpMessageType(this.value);

  static RtmpMessageType fromInt(int value) {
    return RtmpMessageType.values.firstWhere((e) => e.value == value);
  }
}

/// A complete RTMP message before chunking or after reassembly.
class RtmpMessage {
  final int chunkStreamId;
  final RtmpMessageType type;
  final int messageStreamId;
  final int timestamp;
  final Uint8List payload;

  RtmpMessage({
    required this.chunkStreamId,
    required this.type,
    required this.messageStreamId,
    required this.timestamp,
    required this.payload,
  });
}

/// Represents the state of a chunk stream.
class ChunkStreamContext {
  int lastTimestamp = 0;
  int lastTimestampDelta = 0;
  int lastMessageLength = 0;
  int lastMessageTypeId = 0;
  int lastMessageStreamId = 0;
}
