import 'dart:typed_data';
import 'dart:math';
import 'models.dart';

class IncompleteMessage {
  bool isStarted = false;
  int bytesReceived = 0;
  Uint8List payload = Uint8List(0);
}

class ChunkHandler {
  int outChunkSize = 128;
  int inChunkSize = 128;

  final Map<int, ChunkStreamContext> _inContexts = {};
  final Map<int, IncompleteMessage> _incompleteMessages = {};
  final Map<int, ChunkStreamContext> _outContexts = {};

  /// Current buffer for incoming bytes that haven't been processed yet.
  final List<int> _inBuffer = [];

  /// Encodes an [RtmpMessage] into a list of chunks (Uint8List).
  List<Uint8List> encodeMessage(RtmpMessage message) {
    final context = _outContexts.putIfAbsent(
      message.chunkStreamId,
      () => ChunkStreamContext(),
    );
    final List<Uint8List> chunks = [];

    int bytesSent = 0;
    while (bytesSent < message.payload.length) {
      final isFirstChunk = bytesSent == 0;
      final payloadSize = min(outChunkSize, message.payload.length - bytesSent);
      final payloadPart = message.payload.sublist(
        bytesSent,
        bytesSent + payloadSize,
      );

      final header = _buildChunkHeader(
        message,
        context,
        isFirstChunk,
        message.payload.length,
      );

      final chunk = BytesBuilder();
      chunk.add(header);
      chunk.add(payloadPart);
      chunks.add(chunk.toBytes());

      bytesSent += payloadSize;
    }

    context.lastTimestamp = message.timestamp;
    context.lastMessageLength = message.payload.length;
    context.lastMessageTypeId = message.type.value;
    context.lastMessageStreamId = message.messageStreamId;

    return chunks;
  }

  /// Processes incoming bytes and returns a list of reassembled [RtmpMessage]s.
  List<RtmpMessage> handleData(Uint8List data) {
    _inBuffer.addAll(data);
    final List<RtmpMessage> messages = [];

    while (true) {
      if (_inBuffer.isEmpty) break;

      final int firstByte = _inBuffer[0];
      final int fmt = (firstByte >> 6) & 0x03;
      int csid = firstByte & 0x3F;
      int headerSize = 1;

      if (csid == 0) {
        if (_inBuffer.length < 2) break;
        csid = _inBuffer[1] + 64;
        headerSize = 2;
      } else if (csid == 1) {
        if (_inBuffer.length < 3) break;
        csid = (_inBuffer[2] << 8) + _inBuffer[1] + 64;
        headerSize = 3;
      }

      int chunkHeaderSize = 0;
      if (fmt == 0) {
        chunkHeaderSize = 11;
      } else if (fmt == 1)
        chunkHeaderSize = 7;
      else if (fmt == 2)
        chunkHeaderSize = 3;
      else if (fmt == 3)
        chunkHeaderSize = 0;

      if (_inBuffer.length < headerSize + chunkHeaderSize) break;

      final context = _inContexts.putIfAbsent(csid, () => ChunkStreamContext());
      final incomplete = _incompleteMessages.putIfAbsent(
        csid,
        () => IncompleteMessage(),
      );

      int offset = headerSize;
      int timestamp = context.lastTimestamp;
      int delta = context.lastTimestampDelta;
      int length = context.lastMessageLength;
      int typeId = context.lastMessageTypeId;
      int streamId = context.lastMessageStreamId;

      if (fmt <= 2) {
        timestamp = _readUint24(_inBuffer, offset);
        offset += 3;
        if (fmt <= 1) {
          length = _readUint24(_inBuffer, offset);
          offset += 3;
          typeId = _inBuffer[offset++];
          if (fmt == 0) {
            streamId = _readUint32LittleEndian(_inBuffer, offset);
            offset += 4;
          }
        }
      }

      // Extended timestamp
      bool hasExtendedTimestamp =
          (fmt < 3 && timestamp == 0xFFFFFF) ||
          (fmt == 3 && context.lastTimestamp >= 0xFFFFFF);
      if (hasExtendedTimestamp) {
        if (_inBuffer.length < offset + 4) break;
        timestamp = _readUint32(_inBuffer, offset);
        offset += 4;
      }

      if (fmt == 0) {
        delta = 0;
      } else if (fmt == 1 || fmt == 2) {
        delta = timestamp;
        timestamp = context.lastTimestamp + delta;
      } else if (fmt == 3 && !incomplete.isStarted) {
        timestamp = context.lastTimestamp + delta;
      }

      final payloadSize = min(inChunkSize, length - incomplete.bytesReceived);
      if (_inBuffer.length < offset + payloadSize) break;

      // Consume header
      _inBuffer.removeRange(0, offset);

      // Consume payload
      final part = Uint8List.fromList(_inBuffer.sublist(0, payloadSize));
      _inBuffer.removeRange(0, payloadSize);

      if (!incomplete.isStarted) {
        incomplete.payload = Uint8List(length);
        incomplete.isStarted = true;
      }
      incomplete.payload.setAll(incomplete.bytesReceived, part);
      incomplete.bytesReceived += payloadSize;

      context.lastTimestamp = timestamp;
      context.lastTimestampDelta = delta;
      context.lastMessageLength = length;
      context.lastMessageTypeId = typeId;
      context.lastMessageStreamId = streamId;

      if (incomplete.bytesReceived == length) {
        final message = RtmpMessage(
          chunkStreamId: csid,
          type: RtmpMessageType.fromInt(typeId),
          messageStreamId: streamId,
          timestamp: timestamp,
          payload: incomplete.payload,
        );
        messages.add(message);

        // Handle setChunkSize immediately to affect subsequent chunks in the same data batch
        if (message.type == RtmpMessageType.setChunkSize &&
            message.payload.length >= 4) {
          inChunkSize = _readUint32(message.payload, 0);
          print('ChunkHandler: Updated inChunkSize to $inChunkSize');
        }

        _incompleteMessages[csid] = IncompleteMessage(); // Reset
      }
    }

    return messages;
  }

  int _readUint24(List<int> bytes, int offset) {
    return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
  }

  int _readUint32(List<int> bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  int _readUint32LittleEndian(List<int> bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  Uint8List _buildChunkHeader(
    RtmpMessage msg,
    ChunkStreamContext ctx,
    bool isFirst,
    int totalLength,
  ) {
    final builder = BytesBuilder();

    int fmt = isFirst ? 0 : 3;
    builder.addByte((fmt << 6) | msg.chunkStreamId);

    if (fmt == 0) {
      _addUint24(builder, msg.timestamp >= 0xFFFFFF ? 0xFFFFFF : msg.timestamp);
      _addUint24(builder, totalLength);
      builder.addByte(msg.type.value);
      _addUint32LittleEndian(builder, msg.messageStreamId);

      if (msg.timestamp >= 0xFFFFFF) {
        _addUint32(builder, msg.timestamp);
      }
    } else if (fmt == 3) {
      if (ctx.lastTimestamp >= 0xFFFFFF) {
        _addUint32(builder, ctx.lastTimestamp);
      }
    }

    return builder.toBytes();
  }

  void _addUint24(BytesBuilder builder, int value) {
    builder.addByte((value >> 16) & 0xFF);
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte(value & 0xFF);
  }

  void _addUint32(BytesBuilder builder, int value) {
    builder.addByte((value >> 24) & 0xFF);
    builder.addByte((value >> 16) & 0xFF);
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte(value & 0xFF);
  }

  void _addUint32LittleEndian(BytesBuilder builder, int value) {
    builder.addByte(value & 0xFF);
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte((value >> 16) & 0xFF);
    builder.addByte((value >> 24) & 0xFF);
  }
}
