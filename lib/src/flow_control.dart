/// Flow control events emitted by the RTMP server.
sealed class RtmpFlowControlEvent {
  const RtmpFlowControlEvent();
}

/// Acknowledgement from the peer indicating bytes received.
class RtmpAcknowledgement extends RtmpFlowControlEvent {
  final int bytesAcknowledged;

  const RtmpAcknowledgement(this.bytesAcknowledged);
}

/// Server window acknowledgement size announcement.
class RtmpWindowAcknowledgementSize extends RtmpFlowControlEvent {
  final int windowSize;

  const RtmpWindowAcknowledgementSize(this.windowSize);
}

/// Server peer bandwidth notification.
class RtmpPeerBandwidth extends RtmpFlowControlEvent {
  final int bandwidth;
  final int limitType;

  const RtmpPeerBandwidth(this.bandwidth, this.limitType);
}
