import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../flow_control.dart';
import '../amf/amf.dart';
import '../utils/constants.dart';
import '../chunk/chunk_handler.dart';
import '../chunk/models.dart';

/// Audio codecs supported by the RTMP client.
///
/// These values are used to specify supported audio formats during connection.
enum RtmpAudioCodec {
  /// Raw sound, no compression
  none(0x0001),

  /// ADPCM compression
  adpcm(0x0002),

  /// mp3 compression
  mp3(0x0004),

  /// Not used
  @Deprecated('Not used')
  intel(0x0008),

  /// Not used
  @Deprecated('Not used')
  unused(0x0010),

  /// NellyMoser at 8-kHz compression
  nelly8(0x0020),

  /// NellyMoser compression (5, 11, 22, and 44 kHz)
  nelly(0x0040),

  /// G711A sound compression (Flash Media Server only)
  g711a(0x0080),

  /// G711U sound compression (Flash Media Server only)
  g711u(0x0100),

  /// NellyMouser at 16-kHz compression
  nelly16(0x0200),

  /// Advanced audio coding (AAC) codec
  aac(0x0400),

  /// Speex Audio
  speex(0x0800),

  /// All RTMP-supported audio codecs
  all(0x0FFF);

  /// The flag value associated with the codec.
  final int flag;
  const RtmpAudioCodec(this.flag);
}

/// Video codecs supported by the RTMP client.
///
/// These values are used to specify supported video formats during connection.
enum RtmpVideoCodec {
  /// Obsolete value
  @Deprecated('Obsolete value')
  unused(0x0001),

  /// Obsolete value
  @Deprecated('Obsolete value')
  jpeg(0x0002),

  /// Sorenson Flash video
  sorenson(0x0004),

  /// V1 screen sharing
  homebrew(0x0008),

  /// On2 video (Flash 8+)
  vp6(0x0010),

  /// On2 video with alpha channel (Flash 8+)
  vp6Alpha(0x0020),

  /// Screen sharing version 2 (Flash 8+)
  homebrewV(0x0040),

  /// H264 video
  h264(0x0080),

  /// All RTMP-supported video codecs
  all(0x0FFF);

  /// The flag value associated with the codec.
  final int flag;
  const RtmpVideoCodec(this.flag);
}

class RtmpProtocol {
  final ChunkHandler chunkHandler;
  final void Function(Uint8List) onSend;
  final void Function(RtmpFlowControlEvent event)? onFlowControl;

  int _transactionIdCounter = 1;
  final Map<int, Completer<dynamic>> _pendingCommands = {};
  final Map<int, void Function(RtmpMessage)> _streamHandlers = {};

  RtmpProtocol({
    required this.chunkHandler,
    required this.onSend,
    this.onFlowControl,
  });

  void registerStreamHandler(int streamId, void Function(RtmpMessage) handler) {
    _streamHandlers[streamId] = handler;
  }

  void unregisterStreamHandler(int streamId) {
    _streamHandlers.remove(streamId);
  }

  /// Sends a 'connect' command.
  Future<dynamic> connect(
    String app, {
    String? tcUrl,
    bool viaProxy = false,
    Set<RtmpAudioCodec> audioCodecs = const {RtmpAudioCodec.all},
    Set<RtmpVideoCodec> videoCodecs = const {RtmpVideoCodec.all},
  }) {
    final args = {
      'app': app,
      'flashVer':
          'FMLE/3.0 (compatible; Dart/${Platform.version.split(' ').first})',
      'tcUrl': tcUrl ?? 'rtmp://localhost/$app',
      'fpad': viaProxy,
      'audioCodecs': (audioCodecs.fold(
        0,
        (previousValue, element) => previousValue | element.flag,
      )).toDouble(),
      'videoCodecs': (videoCodecs.fold(
        0,
        (previousValue, element) => previousValue | element.flag,
      )).toDouble(),
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

  /// Sends a 'play' command.
  void play(int streamId, String streamName) {
    sendMessage(
      chunkStreamId: 3,
      type: RtmpMessageType.commandMessageAmf0,
      messageStreamId: streamId,
      timestamp: 0,
      payload: encodeAmf(['play', 0.0, null, streamName]),
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
        if (message.payload.length >= 4) {
          final data = ByteData.sublistView(message.payload);
          final size = data.getUint32(0, Endian.big);
          onFlowControl?.call(RtmpWindowAcknowledgementSize(size));
        }
        break;
      case RtmpMessageType.acknowledgement:
        if (message.payload.length >= 4) {
          final data = ByteData.sublistView(message.payload);
          final size = data.getUint32(0, Endian.big);
          onFlowControl?.call(RtmpAcknowledgement(size));
        }
        break;
      case RtmpMessageType.setPeerBandwidth:
        if (message.payload.length >= 4) {
          final data = ByteData.sublistView(message.payload);
          final size = data.getUint32(0, Endian.big);
          final limitType = message.payload.length >= 5 ? data.getUint8(4) : 0;
          onFlowControl?.call(RtmpPeerBandwidth(size, limitType));
        }
        break;
      case RtmpMessageType.userControlMessage:
        _handleUserControl(message.payload);
        break;
      case RtmpMessageType.audioMessage:
      case RtmpMessageType.videoMessage:
      case RtmpMessageType.dataMessageAmf0:
        final handler = _streamHandlers[message.messageStreamId];
        if (handler != null) {
          handler(message);
        }
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
