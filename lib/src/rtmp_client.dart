import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'handshake/handshake.dart';
import 'chunk/chunk_handler.dart';
import 'chunk/models.dart';
import 'package:rtmp/src/utils/constants.dart';
import 'protocol/protocol.dart';

class RtmpClient {
  late Socket _socket;
  late ChunkHandler _chunkHandler;
  late RtmpProtocol _protocol;

  final _messageController = StreamController<void>();

  Future<void> connect(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'rtmp' && uri.scheme != 'rtmps') {
      throw ArgumentError(
        'Only rtmp and rtmps schemes are supported currently',
      );
    }

    final host = uri.host;
    final port = uri.port == 0 ? 1935 : uri.port;
    final app = uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : '';
    final isSecure = uri.scheme == 'rtmps';

    // 1. Prepare broadcast stream for shared listening
    final socket = isSecure
        ? await SecureSocket.connect(host, port)
        : await Socket.connect(host, port);
    _socket = socket;

    final controller = StreamController<Uint8List>.broadcast();
    _socket.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    final reader = controller.stream;

    int bytesToSkip = 1 + Handshake.handshakeSize * 2;

    _chunkHandler = ChunkHandler();
    _protocol = RtmpProtocol(
      chunkHandler: _chunkHandler,
      onSend: (data) => _socket.add(data),
    );

    // tcUrl should be rtmp://host:port/app
    final tcUrl = url;
    print('Connecting with tcUrl: $tcUrl');

    // 2. Start protocol listener EARLY to catch coalesced data
    reader.listen(
      (data) {
        Uint8List payload;
        if (bytesToSkip > 0) {
          if (data.length <= bytesToSkip) {
            bytesToSkip -= data.length;
            return;
          } else {
            payload = Uint8List.sublistView(data, bytesToSkip);
            bytesToSkip = 0;
          }
        } else {
          payload = data;
        }

        final messages = _chunkHandler.handleData(payload);
        for (var msg in messages) {
          print(
            'Incoming message: type=${msg.type}, size=${msg.payload.length}',
          );
          _protocol.handleMessage(msg);
        }
      },
      onError: (e) => print('Socket error: $e'),
      onDone: () => print('Socket closed'),
    );

    // 3. Handshake
    await Handshake.perform(
      _socket,
      reader,
    ).timeout(const Duration(seconds: 15));

    // 4. Connect Command
    await _protocol
        .connect(app, tcUrl: tcUrl)
        .timeout(const Duration(seconds: 15));

    // 5. Initial Control Messages (Optional, sent after connect)
    _protocol.setChunkSize(4096);
  }

  Future<RtmpStream> createStream() async {
    final streamId = await _protocol.createStream();
    return RtmpStream(streamId, _protocol);
  }

  Future<void> close() async {
    await _socket.close();
    await _messageController.close();
  }
}

class RtmpStream {
  final int streamId;
  final RtmpProtocol _protocol;

  RtmpStream(this.streamId, this._protocol);

  /// Starts publishing a stream with the given [streamKey].
  Future<void> publish(String streamKey) async {
    _protocol.publish(streamId, streamKey, 'live');
  }

  /// Sends a video data packet.
  void sendVideo(Uint8List data, int timestamp) {
    _protocol.sendMessage(
      chunkStreamId: 4,
      type: RtmpMessageType.videoMessage,
      messageStreamId: streamId,
      timestamp: timestamp,
      payload: data,
    );
  }

  /// Sends H.264 AVCDecoderConfigurationRecord (SPS/PPS).
  void sendH264SequenceHeader(Uint8List avcC) {
    final payload = BytesBuilder();
    payload.addByte(
      (RtmpConstants.flvVideoFrameTypeKeyframe << 4) |
          RtmpConstants.flvVideoCodecIdAvc,
    );
    payload.addByte(RtmpConstants.avcPacketTypeSequenceHeader);
    payload.addByte(0x00); // CompositionTime
    payload.addByte(0x00);
    payload.addByte(0x00);
    payload.add(avcC);

    sendVideo(payload.toBytes(), 0);
  }

  /// Sends H.264 NALU sample.
  void sendH264Sample(
    Uint8List data,
    int timestamp, {
    bool isKeyframe = false,
  }) {
    final payload = BytesBuilder();
    final frameType = isKeyframe
        ? RtmpConstants.flvVideoFrameTypeKeyframe
        : RtmpConstants.flvVideoFrameTypeInter;
    payload.addByte((frameType << 4) | RtmpConstants.flvVideoCodecIdAvc);
    payload.addByte(RtmpConstants.avcPacketTypeNalu);
    payload.addByte(0x00); // CompositionTime
    payload.addByte(0x00);
    payload.addByte(0x00);
    payload.add(data);

    sendVideo(payload.toBytes(), timestamp);
  }

  /// Sends AAC AudioSpecificConfig.
  void sendAACSequenceHeader(Uint8List config) {
    final payload = BytesBuilder();
    // AudioTagHeader:
    // Format 10 (AAC) << 4 | Rate 3 (44kHz) << 2 | Size 1 (16 bit) << 1 | Type 1 (Stereo)
    const audioHeader =
        (RtmpConstants.flvAudioFormatAac << 4) |
        (RtmpConstants.flvAudioRate44kHz << 2) |
        (RtmpConstants.flvAudioSize16Bit << 1) |
        RtmpConstants.flvAudioTypeStereo;
    payload.addByte(audioHeader);
    payload.addByte(RtmpConstants.aacPacketTypeSequenceHeader);
    payload.add(config);

    sendAudio(payload.toBytes(), 0);
  }

  /// Sends AAC NALU sample.
  void sendAACSample(Uint8List data, int timestamp) {
    final payload = BytesBuilder();
    const audioHeader =
        (RtmpConstants.flvAudioFormatAac << 4) |
        (RtmpConstants.flvAudioRate44kHz << 2) |
        (RtmpConstants.flvAudioSize16Bit << 1) |
        RtmpConstants.flvAudioTypeStereo;
    payload.addByte(audioHeader);
    payload.addByte(RtmpConstants.aacPacketTypeRaw);
    payload.add(data);

    sendAudio(payload.toBytes(), timestamp);
  }

  /// Sends an audio data packet.
  void sendAudio(Uint8List data, int timestamp) {
    _protocol.sendMessage(
      chunkStreamId: 4,
      type: RtmpMessageType.audioMessage,
      messageStreamId: streamId,
      timestamp: timestamp,
      payload: data,
    );
  }

  /// Sends metadata.
  void sendMetadata(Map<String, dynamic> metadata) {
    _protocol.sendMessage(
      chunkStreamId: 3,
      type: RtmpMessageType.dataMessageAmf0,
      messageStreamId: streamId,
      timestamp: 0,
      payload: _protocol.encodeAmf(['@setDataFrame', 'onMetaData', metadata]),
    );
  }
}
