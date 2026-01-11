import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'handshake/handshake.dart';
import 'amf/amf.dart';
import 'chunk/chunk_handler.dart';
import 'chunk/models.dart';
import 'flow_control.dart';
import 'package:rtmp/src/utils/constants.dart';
import 'protocol/protocol.dart';

/// A client that implements the Real-Time Messaging Protocol (RTMP).
///
/// This client supports both publishing and receiving streams.
/// It works for both `rtmp://` and `rtmps://` (secure) connections.
class RtmpClient {
  late Socket _socket;
  late ChunkHandler _chunkHandler;
  late RtmpProtocol _protocol;

  final _messageController = StreamController<void>();
  final _flowControlController =
      StreamController<RtmpFlowControlEvent>.broadcast();

  /// A stream of flow-control events from the server.
  Stream<RtmpFlowControlEvent> get flowControlStream =>
      _flowControlController.stream;

  /// Connects to an RTMP/RTMPS server.
  ///
  /// [url] should be in the format `rtmp://host:port/app` or `rtmps://host:port/app`.
  /// [viaProxy] indicates whether the connection is through a proxy (fpAd).
  /// [audioCodecs] and [videoCodecs] specify the supported codecs for this connection.
  /// [ignoreCertificateErrors] can be set to true for RTMPS connections with self-signed certificates.
  Future<void> connect(
    String url, {
    bool viaProxy = false,
    Set<RtmpAudioCodec> audioCodecs = const {RtmpAudioCodec.all},
    Set<RtmpVideoCodec> videoCodecs = const {RtmpVideoCodec.all},
    bool ignoreCertificateErrors = false,
  }) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'rtmp' && uri.scheme != 'rtmps') {
      throw ArgumentError(
        'Only rtmp and rtmps schemes are supported currently',
      );
    }

    final host = uri.host;
    final isSecure = uri.scheme == 'rtmps';
    final port = uri.port != 0 ? uri.port : (isSecure ? 443 : 1935);
    final app = uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : '';

    // 1. Prepare broadcast stream for shared listening
    final socket = isSecure
        ? await SecureSocket.connect(
            host,
            port,
            onBadCertificate: ignoreCertificateErrors ? (cert) => true : null,
          )
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
      onFlowControl: _flowControlController.add,
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
        .connect(
          app,
          tcUrl: tcUrl,
          viaProxy: viaProxy,
          audioCodecs: audioCodecs,
          videoCodecs: videoCodecs,
        )
        .timeout(const Duration(seconds: 15));

    // 5. Initial Control Messages (Optional, sent after connect)
    _protocol.setChunkSize(4096);
  }

  /// Creates a new RTMP stream within the current connection.
  ///
  /// Returns an [RtmpStream] that can be used to [RtmpStream.publish] or [RtmpStream.play].
  Future<RtmpStream> createStream() async {
    final streamId = await _protocol.createStream();
    return RtmpStream(streamId, _protocol);
  }

  /// Sets the outgoing chunk size.
  void setChunkSize(int size) {
    _protocol.setChunkSize(size);
  }

  /// Closes the connection and all associated streams.
  Future<void> close() async {
    await _socket.close();
    await _messageController.close();
    await _flowControlController.close();
  }
}

/// Represents a single RTMP stream within a connection.
///
/// Use [RtmpClient.createStream] to create an instance of this class.
class RtmpStream {
  /// The unique ID of this stream.
  final int streamId;
  final RtmpProtocol _protocol;

  final _videoController = StreamController<RtmpMediaPacket>.broadcast();
  final _audioController = StreamController<RtmpMediaPacket>.broadcast();
  final _metadataController =
      StreamController<Map<String, dynamic>>.broadcast();

  RtmpStream(this.streamId, this._protocol) {
    _protocol.registerStreamHandler(streamId, _onMessage);
  }

  /// A stream of video packets received from the server.
  Stream<RtmpMediaPacket> get videoStream => _videoController.stream;

  /// A stream of audio packets received from the server.
  Stream<RtmpMediaPacket> get audioStream => _audioController.stream;

  /// A stream of metadata maps received from the server (e.g., onMetaData).
  Stream<Map<String, dynamic>> get metadataStream => _metadataController.stream;

  void _onMessage(RtmpMessage message) {
    switch (message.type) {
      case RtmpMessageType.videoMessage:
        _videoController.add(
          RtmpMediaPacket(message.payload, message.timestamp),
        );
        break;
      case RtmpMessageType.audioMessage:
        _audioController.add(
          RtmpMediaPacket(message.payload, message.timestamp),
        );
        break;
      case RtmpMessageType.dataMessageAmf0:
        final decoder = Amf0Decoder(message.payload);
        final name = decoder.decode();
        if (name == 'onMetaData' && decoder.hasMore) {
          final metadata = decoder.decode();
          if (metadata is Map<String, dynamic>) {
            _metadataController.add(metadata);
          }
        }
        break;
      default:
        break;
    }
  }

  /// Starts publishing a stream with the given [streamKey].
  Future<void> publish(String streamKey) async {
    _protocol.publish(streamId, streamKey, 'live');
  }

  /// Starts playing a stream with the given [streamKey].
  Future<void> play(String streamKey) async {
    _protocol.play(streamId, streamKey);
  }

  /// Sends a raw video data packet.
  ///
  /// For H.264, usually you should use [sendH264SequenceHeader] and [sendH264Sample] instead.
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
  void sendH264SequenceHeader(Uint8List avcC, {int timestamp = 0}) {
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

    sendVideo(payload.toBytes(), timestamp);
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
      chunkStreamId: 5,
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

  /// Closes the stream.
  Future<void> close() async {
    _protocol.unregisterStreamHandler(streamId);
    await _videoController.close();
    await _audioController.close();
    await _metadataController.close();
  }
}

/// A media packet received from or sent to an RTMP stream.
class RtmpMediaPacket {
  /// The raw payload of the media packet.
  final Uint8List data;

  /// The timestamp of the packet in milliseconds.
  final int timestamp;

  RtmpMediaPacket(this.data, this.timestamp);
}
