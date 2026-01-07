import 'package:test/test.dart';
import 'package:rtmp/src/amf/amf.dart';

void main() {
  group('AMF0 Encoder/Decoder', () {
    test('Number', () {
      final encoder = Amf0Encoder();
      encoder.encode(123.45);
      final decoder = Amf0Decoder(encoder.bytes);
      expect(decoder.decode(), equals(123.45));
    });

    test('Boolean', () {
      final encoder = Amf0Encoder();
      encoder.encode(true);
      encoder.encode(false);
      final decoder = Amf0Decoder(encoder.bytes);
      expect(decoder.decode(), isTrue);
      expect(decoder.decode(), isFalse);
    });

    test('String', () {
      final encoder = Amf0Encoder();
      encoder.encode('Hello RTMP');
      final decoder = Amf0Decoder(encoder.bytes);
      expect(decoder.decode(), equals('Hello RTMP'));
    });

    test('Null', () {
      final encoder = Amf0Encoder();
      encoder.encode(null);
      final decoder = Amf0Decoder(encoder.bytes);
      expect(decoder.decode(), isNull);
    });

    test('Object', () {
      final encoder = Amf0Encoder();
      final input = {'key': 'value', 'num': 42.0};
      encoder.encode(input);
      final decoder = Amf0Decoder(encoder.bytes);
      expect(decoder.decode(), equals(input));
    });

    test('Strict Array', () {
      final encoder = Amf0Encoder();
      final input = [1.0, 'two', true];
      encoder.encode(input);
      final decoder = Amf0Decoder(encoder.bytes);
      expect(decoder.decode(), equals(input));
    });
  });
}
