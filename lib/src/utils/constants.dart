/// RTMP Mixed Constants
class RtmpConstants {
  // Codec Flag Values for audioCodecs property
  static const int supportSndNone = 0x0001;
  static const int supportSndAdpcm = 0x0002;
  static const int supportSndMp3 = 0x0004;
  static const int supportSndIntel = 0x0008;
  static const int supportSndUnused = 0x0010;
  static const int supportSndNelly8 = 0x0020;
  static const int supportSndNelly = 0x0040;
  static const int supportSndG711a = 0x0080;
  static const int supportSndG711u = 0x0100;
  static const int supportSndNelly16 = 0x0200;
  static const int supportSndAac = 0x0400;
  static const int supportSndSpeex = 0x0800;
  static const int supportSndAll = 0x0FFF;

  // Codec Flag Values for videoCodecs property
  static const int supportVidUnused = 0x0001;
  static const int supportVidJpeg = 0x0002;
  static const int supportVidSorenson = 0x0004;
  static const int supportVidHomebrew = 0x0008;
  static const int supportVidVp6 = 0x0010;
  static const int supportVidVp6alpha = 0x0020;
  static const int supportVidHomebrewv = 0x0040;
  static const int supportVidH264 = 0x0080;
  static const int supportVidAll = 0x00FF;

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

/// MP4 Descriptor Tags
class Mp4DescriptorTags {
  static const int esDescriptor = 0x03;
  static const int decoderConfigDescriptor = 0x04;
  static const int decoderSpecificInfo = 0x05;
}
