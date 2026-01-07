/// A pure Dart implementation of the Real-Time Messaging Protocol (RTMP).
///
/// This package provides an [RtmpClient] that can be used to connect to RTMP
/// servers for both publishing and receiving media streams.
library;

export 'src/rtmp_client.dart';
export 'src/protocol/protocol.dart' show RtmpAudioCodec, RtmpVideoCodec;
