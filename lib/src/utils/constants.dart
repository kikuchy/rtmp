/// RTMP Mixed Constants
class RtmpConstants {
  // Function Flag Values for videoFunction property
  static const int supportVidClientSeek = 1;

  // FLV Video Tag Constants
  static const int flvVideoFrameTypeKeyframe = 1;
  static const int flvVideoFrameTypeInter = 2;

  // FLV Video Codec IDs
  static const int flvVideoCodecIdSorenson = 2;
  static const int flvVideoCodecIdScreen = 3;
  static const int flvVideoCodecIdVp6 = 4;
  static const int flvVideoCodecIdVp6Alpha = 5;
  static const int flvVideoCodecIdScreenV2 = 6;
  static const int flvVideoCodecIdAvc = 7;

  // FLV Audio Tag Constants
  static const int flvAudioRate44kHz = 3;
  static const int flvAudioSize16Bit = 1;
  static const int flvAudioTypeStereo = 1;

  // FLV Audio Formats
  static const int flvAudioFormatLinearPcmPlatformEnd = 0;
  static const int flvAudioFormatAdpcm = 1;
  static const int flvAudioFormatMp3 = 2;
  static const int flvAudioFormatLinearPcmLittleEnd = 3;
  static const int flvAudioFormatNellymoser16kHzMono = 4;
  static const int flvAudioFormatNellymoser8kHzMono = 5;
  static const int flvAudioFormatNellymoser = 6;
  static const int flvAudioFormatG711aLawLogarithmicPcm = 7;
  static const int flvAudioFormatG711uLawLogarithmicPcm = 8;
  static const int flvAudioFormatReserved = 9;
  static const int flvAudioFormatAac = 10;
  static const int flvAudioFormatSpeex = 11;
  static const int flvAudioFormatMp3_8kHz = 14;
  static const int flvAudioFormatDeviceSpecificSound = 15;

  // AAC Packet Types
  static const int aacPacketTypeSequenceHeader = 0;
  static const int aacPacketTypeRaw = 1;

  // AVC Packet Types
  static const int avcPacketTypeSequenceHeader = 0;
  static const int avcPacketTypeNalu = 1;
  static const int avcPacketTypeEndOfSequence = 2;
}
