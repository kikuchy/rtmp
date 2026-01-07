import 'dart:async';
import 'dart:typed_data';
import '../amf/amf.dart';
import '../utils/constants.dart';
import '../chunk/chunk_handler.dart';
import '../chunk/models.dart';

class RtmpProtocol {
  final ChunkHandler chunkHandler;
  final void Function(Uint8List) onSend;

  int _transactionIdCounter = 1;
  final Map<int, Completer<dynamic>> _pendingCommands = {};

  RtmpProtocol({required this.chunkHandler, required this.onSend});

  /// Sends a 'connect' command.
  Future<dynamic> connect(String app, {String? tcUrl}) {
    final args = {
      'app': app,
      'flashVer': 'FMLE/3.0 (compatible; Antigravity)',
      'tcUrl': tcUrl ?? 'rtmp://localhost/$app',
      'fpad': false,
      'capabilities': 15.0, // Should also be constants if possible
      'audioCodecs':
          (RtmpConstants.supportSndAac |
                  RtmpConstants.supportSndSpeex |
                  RtmpConstants.supportSndNelly16 |
                  RtmpConstants.supportSndNelly |
                  RtmpConstants.supportSndMp3 |
                  RtmpConstants.supportSndAdpcm |
                  RtmpConstants.supportSndNone |
                  RtmpConstants.supportSndG711a |
                  RtmpConstants.supportSndG711u)
              .toDouble(),
      'videoCodecs':
          (RtmpConstants.supportVidH264 |
                  RtmpConstants.supportVidVp6alpha |
                  RtmpConstants.supportVidVp6 |
                  RtmpConstants.supportVidHomebrewv |
                  RtmpConstants.supportVidHomebrew |
                  RtmpConstants.supportVidSorenson)
              .toDouble(),
      'videoFunction': RtmpConstants.supportVidClientSeek.toDouble(),
    };
    return _sendCommand('connect', [args]);
  }

  /// Sets the outgoing chunk size.
  void setChunkSize(int size) {
    chunkHandler.outChunkSize = size;
    final payload = ByteData(4)..setUint32(0, size, Endian.big);
    sendMessage(
      chunkStreamId: 2,
      type: RtmpMessageType.setChunkSize,
      messageStreamId: 0,
      timestamp: 0,
      payload: payload.buffer.asUint8List(),
    );
  }

  /// Sets the window acknowledgement size.
  void setWindowAcknowledgementSize(int size) {
    final payload = ByteData(4)..setUint32(0, size, Endian.big);
    sendMessage(
      chunkStreamId: 2,
      type: RtmpMessageType.windowAcknowledgementSize,
      messageStreamId: 0,
      timestamp: 0,
      payload: payload.buffer.asUint8List(),
    );
  }

  /// Sets the peer bandwidth.
  void setPeerBandwidth(int size, int limitType) {
    final payload = ByteData(5)
      ..setUint32(0, size, Endian.big)
      ..setUint8(4, limitType);
    sendMessage(
      chunkStreamId: 2,
      type: RtmpMessageType.setPeerBandwidth,
      messageStreamId: 0,
      timestamp: 0,
      payload: payload.buffer.asUint8List(),
    );
  }

  /// Sends a 'createStream' command.
  Future<int> createStream() async {
    final result = await _sendCommand('createStream', [null]);
    return (result as double).toInt();
  }

  /// Sends a 'publish' command.
  void publish(int streamId, String streamName, String mode) {
    sendMessage(
      chunkStreamId: 3,
      type: RtmpMessageType.commandMessageAmf0,
      messageStreamId: streamId,
      timestamp: 0,
      payload: encodeAmf(['publish', 0.0, null, streamName, mode]),
    );
  }

  void handleMessage(RtmpMessage message) {
    switch (message.type) {
      case RtmpMessageType.commandMessageAmf0:
        _handleCommand(message.payload);
        break;
      case RtmpMessageType.setChunkSize:
        final data = ByteData.sublistView(message.payload);
        final size = data.getUint32(0, Endian.big);
        print('Server set chunk size to: $size');
        chunkHandler.inChunkSize = size;
        break;
      case RtmpMessageType.windowAcknowledgementSize:
        final data = ByteData.sublistView(message.payload);
        final size = data.getUint32(0, Endian.big);
        print('Server set window ack size to: $size');
        break;
      case RtmpMessageType.setPeerBandwidth:
        final data = ByteData.sublistView(message.payload);
        final size = data.getUint32(0, Endian.big);
        print('Server set peer bandwidth to: $size');
        break;
      case RtmpMessageType.userControlMessage:
        _handleUserControl(message.payload);
        break;
      default:
        // Already logged the type in RtmpClient
        break;
    }
  }

  void _handleUserControl(Uint8List payload) {
    if (payload.length < 2) return;
    final view = ByteData.sublistView(payload);
    final eventType = view.getUint16(0, Endian.big);
    print('Incoming User Control Event: $eventType');

    if (eventType == 6) {
      // Ping Request (6), respond with Ping Response (7)
      final pingResponse = ByteData(6)
        ..setUint16(0, 7, Endian.big)
        ..setUint32(2, view.getUint32(2, Endian.big), Endian.big);
      sendMessage(
        chunkStreamId: 2,
        type: RtmpMessageType.userControlMessage,
        messageStreamId: 0,
        timestamp: 0,
        payload: pingResponse.buffer.asUint8List(),
      );
    }
  }

  Future<dynamic> _sendCommand(String commandName, List<dynamic> args) {
    final transactionId = (_transactionIdCounter++).toDouble();
    final completer = Completer<dynamic>();
    _pendingCommands[transactionId.toInt()] = completer;

    final List<dynamic> payload = [commandName, transactionId];
    payload.addAll(args);

    print('Sending command: $commandName (tid: $transactionId)');
    sendMessage(
      chunkStreamId: 3,
      type: RtmpMessageType.commandMessageAmf0,
      messageStreamId: 0,
      timestamp: 0,
      payload: encodeAmf(payload),
    );

    return completer.future;
  }

  void _handleCommand(Uint8List payload) {
    final decoder = Amf0Decoder(payload);
    final commandName = decoder.decode() as String;
    final transactionId = (decoder.decode() as double).toInt();
    decoder.decode(); // Skip command object
    final response = decoder.hasMore ? decoder.decode() : null;

    print(
      'Received command: $commandName (tid: $transactionId), response: $response',
    );

    if (commandName == '_result') {
      final completer = _pendingCommands.remove(transactionId);
      completer?.complete(response);
    } else if (commandName == '_error') {
      final completer = _pendingCommands.remove(transactionId);
      completer?.completeError(Exception('Command error: $response'));
    } else if (commandName == 'onStatus') {
      // Handling status updates for publish/play
      print('Status: $response');
    }
  }

  void sendMessage({
    required int chunkStreamId,
    required RtmpMessageType type,
    required int messageStreamId,
    required int timestamp,
    required Uint8List payload,
  }) {
    final msg = RtmpMessage(
      chunkStreamId: chunkStreamId,
      type: type,
      messageStreamId: messageStreamId,
      timestamp: timestamp,
      payload: payload,
    );
    final chunks = chunkHandler.encodeMessage(msg);
    for (var chunk in chunks) {
      onSend(chunk);
    }
  }

  Uint8List encodeAmf(List<dynamic> values) {
    final encoder = Amf0Encoder();
    for (var v in values) {
      encoder.encode(v);
    }
    return encoder.bytes;
  }
}
