import 'dart:typed_data';
import 'dart:io';
import 'package:rtmp/src/utils/constants.dart';

class Mp4Parser {
  final RandomAccessFile _file;

  Mp4Parser(this._file);

  Future<Mp4Track?> findH264Track() async {
    final root = await _parseAtoms(0, await _file.length());
    final moov = root.firstWhere(
      (a) => a.type == 'moov',
      orElse: () => throw Exception('moov not found'),
    );

    for (var trak in moov.children.where((a) => a.type == 'trak')) {
      final mdia = trak.children.firstWhere((a) => a.type == 'mdia');
      final minf = mdia.children.firstWhere((a) => a.type == 'minf');
      final stbl = minf.children.firstWhere((a) => a.type == 'stbl');
      final stsd = stbl.children.firstWhere((a) => a.type == 'stsd');

      // stsd payload: 4 bytes (version/flags) + 4 bytes (count) + 4 bytes (first entry size) + 4 bytes (type)
      if (stsd.data.length >= 16) {
        final entryType = String.fromCharCodes(stsd.data.sublist(12, 16));
        print('Found track entry type: $entryType');
        if (entryType == 'avc1' || entryType == 'avc2' || entryType == 'avc3') {
          return Mp4Track(stbl, _file, Mp4TrackType.video);
        }
      }
    }
    return null;
  }

  Future<Mp4Track?> findAACTrack() async {
    final root = await _parseAtoms(0, await _file.length());
    final moov = root.firstWhere(
      (a) => a.type == 'moov',
      orElse: () => throw Exception('moov not found'),
    );

    for (var trak in moov.children.where((a) => a.type == 'trak')) {
      final mdia = trak.children.firstWhere((a) => a.type == 'mdia');
      final minf = mdia.children.firstWhere((a) => a.type == 'minf');
      final stbl = minf.children.firstWhere((a) => a.type == 'stbl');
      final stsd = stbl.children.firstWhere((a) => a.type == 'stsd');

      if (stsd.data.length >= 16) {
        final entryType = String.fromCharCodes(stsd.data.sublist(12, 16));
        if (entryType == 'mp4a') {
          return Mp4Track(stbl, _file, Mp4TrackType.audio);
        }
      }
    }
    return null;
  }

  Future<List<Atom>> _parseAtoms(int offset, int limit) async {
    final List<Atom> atoms = [];
    int pos = offset;
    while (pos < limit) {
      await _file.setPosition(pos);
      final header = await _file.read(8);
      if (header.length < 8) break;

      final view = ByteData.sublistView(header);
      int size = view.getUint32(0);
      final type = String.fromCharCodes(header.sublist(4, 8));

      if (size == 1) {
        // 64-bit size
        final largeHeader = await _file.read(8);
        size = ByteData.sublistView(largeHeader).getUint64(0);
      } else if (size == 0) {
        // size until end of file
        size = limit - pos;
      }

      final atom = Atom(type, pos, size);

      // Some atoms have children
      if (['moov', 'trak', 'mdia', 'minf', 'stbl'].contains(type)) {
        atom.children = await _parseAtoms(pos + 8, pos + size);
        for (var child in atom.children) {
          child.parent = atom;
        }
      } else {
        await _file.setPosition(pos + 8);
        atom.data = await _file.read(size - 8);
      }

      atoms.add(atom);
      pos += size;
    }
    return atoms;
  }
}

class Atom {
  final String type;
  final int offset;
  final int size;
  Atom? parent;
  List<Atom> children = [];
  Uint8List data = Uint8List(0);

  Atom(this.type, this.offset, this.size);
}

enum Mp4TrackType { video, audio }

class Mp4Track {
  final Atom stbl;
  final RandomAccessFile file;
  final Mp4TrackType type;

  Mp4Track(this.stbl, this.file, this.type);

  int get timescale {
    // stbl -> minf -> mdia -> mdhd
    final minf = stbl.parent!;
    final mdia = minf.parent!;
    final mdhd = mdia.children.firstWhere((a) => a.type == 'mdhd');
    final data = ByteData.sublistView(mdhd.data);
    final version = data.getUint8(0);
    return version == 0 ? data.getUint32(12) : data.getUint32(20);
  }

  Uint8List get avcC {
    final stsd = stbl.children.firstWhere((a) => a.type == 'stsd');
    final data = stsd.data;
    for (var i = 4; i < data.length - 4; i++) {
      if (data[i] == 0x61 &&
          data[i + 1] == 0x76 &&
          data[i + 2] == 0x63 &&
          data[i + 3] == 0x43) {
        final boxOffset = i - 4;
        final size = ByteData.sublistView(
          data.sublist(boxOffset, i),
        ).getUint32(0);
        final end = boxOffset + size;
        if (end > data.length) continue;
        return data.sublist(i + 4, end);
      }
    }
    throw Exception('avcC not found');
  }

  Uint8List get aacConfig {
    final stsd = stbl.children.firstWhere((a) => a.type == 'stsd');
    final data = stsd.data;
    // Look for esds box tag 'esds'
    for (var i = 0; i < data.length - 4; i++) {
      if (data[i] == 0x65 &&
          data[i + 1] == 0x73 &&
          data[i + 2] == 0x64 &&
          data[i + 3] == 0x73) {
        final boxData = data.sublist(i + 4);
        int pos = 4; // Skip version/flags

        Uint8List? findDescriptor(Uint8List d, int targetTag) {
          int p = 0;
          while (p < d.length) {
            int tag = d[p++];
            int len = 0;
            // Read variable length
            for (int k = 0; k < 4; k++) {
              if (p >= d.length) return null;
              int b = d[p++];
              len = (len << 7) | (b & 0x7F);
              if ((b & 0x80) == 0) break;
            }

            if (tag == targetTag) {
              return d.sublist(p, p + len);
            }

            if (tag == Mp4DescriptorTags.esDescriptor) {
              // ES_Descriptor
              if (p + 3 > d.length) return null;
              p += 3; // Skip 2 bytes (id) + 1 byte (flags)
              final sub = findDescriptor(d.sublist(p, p + len - 3), targetTag);
              if (sub != null) return sub;
            } else if (tag == Mp4DescriptorTags.decoderConfigDescriptor) {
              // DecoderConfigDescriptor
              if (p + 13 > d.length) return null;
              p += 13; // Skip 13 bytes of fixed header
              final sub = findDescriptor(d.sublist(p, p + len - 13), targetTag);
              if (sub != null) return sub;
            }
            p += len;
          }
          return null;
        }

        final config = findDescriptor(
          boxData.sublist(pos),
          Mp4DescriptorTags.decoderSpecificInfo,
        );
        if (config != null) return config;
      }
    }
    throw Exception('AAC config (esds/DecoderSpecificInfo) not found');
  }

  Future<List<int>> getSampleDurations() async {
    final stts = stbl.children.firstWhere((a) => a.type == 'stts');
    final data = ByteData.sublistView(stts.data);
    final entryCount = data.getUint32(4);
    final durations = <int>[];
    for (var i = 0; i < entryCount; i++) {
      final count = data.getUint32(8 + i * 8);
      final delta = data.getUint32(12 + i * 8);
      for (var j = 0; j < count; j++) {
        durations.add(delta);
      }
    }
    return durations;
  }

  Future<List<Uint8List>> getSamples() async {
    final stco = stbl.children.firstWhere((a) => a.type == 'stco');
    final stsz = stbl.children.firstWhere((a) => a.type == 'stsz');
    final stsc = stbl.children.firstWhere((a) => a.type == 'stsc');

    final stcoData = ByteData.sublistView(stco.data);
    final chunkCount = stcoData.getUint32(4);
    final chunkOffsets = List.generate(
      chunkCount,
      (i) => stcoData.getUint32(8 + i * 4),
    );

    final stszData = ByteData.sublistView(stsz.data);
    final sampleCount = stszData.getUint32(8);
    final sampleSizes = List.generate(
      sampleCount,
      (i) => stszData.getUint32(12 + i * 4),
    );

    final stscData = ByteData.sublistView(stsc.data);
    final entryCount = stscData.getUint32(4);
    final stscEntries = List.generate(entryCount, (i) {
      return {
        'firstChunk': stscData.getUint32(8 + i * 12),
        'samplesPerChunk': stscData.getUint32(12 + i * 12),
        'sampleDescriptionIndex': stscData.getUint32(16 + i * 12),
      };
    });

    final samples = <Uint8List>[];
    int currentSample = 0;
    for (var i = 0; i < chunkCount; i++) {
      final chunkNumber = i + 1;
      // Find the stsc entry for this chunk
      var entryIndex = 0;
      for (var j = 0; j < stscEntries.length; j++) {
        if (stscEntries[j]['firstChunk']! <= chunkNumber) {
          entryIndex = j;
        } else {
          break;
        }
      }
      final samplesInThisChunk = stscEntries[entryIndex]['samplesPerChunk']!;
      int currentOffset = chunkOffsets[i];

      for (var k = 0; k < samplesInThisChunk; k++) {
        if (currentSample >= sampleCount) break;
        final size = sampleSizes[currentSample];
        await file.setPosition(currentOffset);
        samples.add(await file.read(size));
        currentOffset += size;
        currentSample++;
      }
      if (currentSample >= sampleCount) break;
    }

    return samples;
  }
}
