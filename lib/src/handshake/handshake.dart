import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';

class Handshake {
  static const int handshakeSize = 1536;

  /// Performs the RTMP simple handshake.
  static Future<void> perform(Socket socket, Stream<Uint8List> reader) async {
    final targetSize = 1 + handshakeSize + handshakeSize;
    final c0 = Uint8List.fromList([0x03]); // RTMP version 3
    final c1 = _generateRandomBytes(handshakeSize);
    _setTimestamp(c1, 0);
    c1.fillRange(4, 8, 0);

    socket.add(c0);
    socket.add(c1);

    // Read S0 + S1 + S2
    final List<int> response = [];

    final completer = Completer<void>();
    late StreamSubscription sub;

    sub = reader.listen(
      (data) {
        response.addAll(data);
        if (response.length >= targetSize) {
          completer.complete();
        }
      },
      onError: completer.completeError,
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Socket closed during handshake'));
        }
      },
    );

    try {
      await completer.future.timeout(const Duration(seconds: 10));
    } finally {
      await sub.cancel();
    }

    if (response[0] != 0x03) {
      throw Exception(
        'Server returned unsupported RTMP version: ${response[0]}',
      );
    }

    final s1 = Uint8List.fromList(response.sublist(1, 1 + handshakeSize));
    socket.add(s1); // C2

    // If we read more than targetSize, we might need to handle the leftover,
    // but in RTMP simple handshake, S2 is the last part of the first burst.
  }

  static Uint8List _generateRandomBytes(int size) {
    final rand = Random.secure();
    return Uint8List.fromList(List.generate(size, (_) => rand.nextInt(256)));
  }

  static void _setTimestamp(Uint8List buffer, int timestamp) {
    final data = ByteData.view(buffer.buffer);
    data.setUint32(0, timestamp, Endian.big);
  }
}
