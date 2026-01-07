import 'dart:convert';
import 'dart:typed_data';

/// AMF0 Data Types
enum Amf0Type {
  number(0x00),
  boolean(0x01),
  string(0x02),
  object(0x03),
  nullValue(0x05),
  undefined(0x06),
  reference(0x07),
  ecmaArray(0x08),
  objectEnd(0x09),
  strictArray(0x0a),
  date(0x0b),
  longString(0x0c);

  final int value;
  const Amf0Type(this.value);

  static Amf0Type fromInt(int value) {
    return Amf0Type.values.firstWhere((e) => e.value == value);
  }
}

class Amf0Encoder {
  final BytesBuilder _builder = BytesBuilder();

  Uint8List get bytes => _builder.toBytes();

  void encode(dynamic value) {
    if (value is double || value is int) {
      _encodeNumber(value.toDouble());
    } else if (value is bool) {
      _encodeBoolean(value);
    } else if (value is String) {
      _encodeString(value);
    } else if (value == null) {
      _encodeNull();
    } else if (value is Map<String, dynamic>) {
      _encodeObject(value);
    } else if (value is List) {
      _encodeStrictArray(value);
    } else {
      throw ArgumentError('Unsupported AMF0 type: ${value.runtimeType}');
    }
  }

  void _encodeNumber(double value) {
    _builder.addByte(Amf0Type.number.value);
    final data = ByteData(8);
    data.setFloat64(0, value, Endian.big);
    _builder.add(data.buffer.asUint8List());
  }

  void _encodeBoolean(bool value) {
    _builder.addByte(Amf0Type.boolean.value);
    _builder.addByte(value ? 0x01 : 0x00);
  }

  void _encodeString(String value) {
    final utf8Bytes = utf8.encode(value);
    if (utf8Bytes.length <= 0xFFFF) {
      _builder.addByte(Amf0Type.string.value);
      final data = ByteData(2);
      data.setUint16(0, utf8Bytes.length, Endian.big);
      _builder.add(data.buffer.asUint8List());
    } else {
      _builder.addByte(Amf0Type.longString.value);
      final data = ByteData(4);
      data.setUint32(0, utf8Bytes.length, Endian.big);
      _builder.add(data.buffer.asUint8List());
    }
    _builder.add(utf8Bytes);
  }

  void _encodeNull() {
    _builder.addByte(Amf0Type.nullValue.value);
  }

  void _encodeObject(Map<String, dynamic> value) {
    _builder.addByte(Amf0Type.object.value);
    value.forEach((key, val) {
      _encodePropertyName(key);
      encode(val);
    });
    // Object End
    _builder.addByte(0x00);
    _builder.addByte(0x00);
    _builder.addByte(Amf0Type.objectEnd.value);
  }

  void _encodePropertyName(String name) {
    final utf8Bytes = utf8.encode(name);
    final data = ByteData(2);
    data.setUint16(0, utf8Bytes.length, Endian.big);
    _builder.add(data.buffer.asUint8List());
    _builder.add(utf8Bytes);
  }

  void _encodeStrictArray(List value) {
    _builder.addByte(Amf0Type.strictArray.value);
    final data = ByteData(4);
    data.setUint32(0, value.length, Endian.big);
    _builder.add(data.buffer.asUint8List());
    for (var item in value) {
      encode(item);
    }
  }
}

class Amf0Decoder {
  final ByteData _data;
  int _offset = 0;

  Amf0Decoder(Uint8List bytes) : _data = ByteData.sublistView(bytes);

  bool get hasMore => _offset < _data.lengthInBytes;

  dynamic decode() {
    if (!hasMore) return null;
    final typeByte = _data.getUint8(_offset++);
    final type = Amf0Type.fromInt(typeByte);

    switch (type) {
      case Amf0Type.number:
        final val = _data.getFloat64(_offset, Endian.big);
        _offset += 8;
        return val;
      case Amf0Type.boolean:
        return _data.getUint8(_offset++) != 0;
      case Amf0Type.string:
        return _decodeString();
      case Amf0Type.object:
        return _decodeObject();
      case Amf0Type.nullValue:
        return null;
      case Amf0Type.undefined:
        return null;
      case Amf0Type.ecmaArray:
        _offset += 4; // Skip length
        return _decodeObject();
      case Amf0Type.strictArray:
        final len = _data.getUint32(_offset, Endian.big);
        _offset += 4;
        final list = [];
        for (var i = 0; i < len; i++) {
          list.add(decode());
        }
        return list;
      case Amf0Type.longString:
        return _decodeLongString();
      default:
        throw Exception('Unsupported AMF0 type: $type');
    }
  }

  String _decodeString() {
    final len = _data.getUint16(_offset, Endian.big);
    _offset += 2;
    final bytes = _data.buffer.asUint8List(_data.offsetInBytes + _offset, len);
    _offset += len;
    return utf8.decode(bytes);
  }

  String _decodeLongString() {
    final len = _data.getUint32(_offset, Endian.big);
    _offset += 4;
    final bytes = _data.buffer.asUint8List(_data.offsetInBytes + _offset, len);
    _offset += len;
    return utf8.decode(bytes);
  }

  Map<String, dynamic> _decodeObject() {
    final obj = <String, dynamic>{};
    while (true) {
      final keyLen = _data.getUint16(_offset, Endian.big);
      _offset += 2;
      if (keyLen == 0) {
        if (_data.getUint8(_offset) == Amf0Type.objectEnd.value) {
          _offset++;
          break;
        }
        // Empty key is allowed for some objects, but 00 00 09 is end
      }
      final keyBytes = _data.buffer.asUint8List(
        _data.offsetInBytes + _offset,
        keyLen,
      );
      _offset += keyLen;
      final key = utf8.decode(keyBytes);
      obj[key] = decode();
    }
    return obj;
  }
}
