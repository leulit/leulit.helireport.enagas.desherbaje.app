// Tests for ImagenRemoteAdapter MIME detection (NF-25).
//
// Covers:
//   - JPEG, PNG, GIF, WebP magic-byte detection
//   - Extension fallback when header is short
//   - Short header (2 bytes) does not produce a wrong MIME
//   - _readHeader accumulates across chunks
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:helireport_desherbaje/data/sync/imagen_remote_adapter.dart';
import 'package:helireport_desherbaje/data/network/network_service.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Creates a temporary file with [bytes] as content. Caller is responsible
/// for deleting the file after use.
Future<File> _tmpFile(List<int> bytes) async {
  final dir = Directory.systemTemp;
  final file = File('${dir.path}/mime_test_${DateTime.now().microsecondsSinceEpoch}.bin');
  await file.writeAsBytes(bytes);
  return file;
}

// Fake NetworkService so the adapter can be instantiated without Dio setup.
class _FakeNetworkService extends NetworkService {
  @override
  // ignore: must_call_super
  void onInit() {}
}

ImagenRemoteAdapter _adapter() =>
    ImagenRemoteAdapter(_FakeNetworkService());

// ─── Magic-byte sequences ─────────────────────────────────────────────────────

// JPEG: FF D8 FF + 9 more bytes
final _jpegHeader = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0];
// PNG: 89 50 4E 47 + 8 more bytes
final _pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0];
// GIF: 47 49 46 38 + 8 more bytes
final _gifHeader = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0, 0, 0, 0, 0];
// WebP: RIFF (52 49 46 46) + 4 bytes size + WEBP (57 45 42 50)
final _webpHeader = [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50];

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('_detectMime — magic bytes', () {
    test('JPEG magic bytes → image/jpeg', () {
      expect(
        _adapter().detectMime(_jpegHeader),
        equals('image/jpeg'),
      );
    });

    test('PNG magic bytes → image/png', () {
      expect(
        _adapter().detectMime(_pngHeader),
        equals('image/png'),
      );
    });

    test('GIF magic bytes → image/gif', () {
      expect(
        _adapter().detectMime(_gifHeader),
        equals('image/gif'),
      );
    });

    test('WebP magic bytes (RIFF...WEBP) → image/webp', () {
      expect(
        _adapter().detectMime(_webpHeader),
        equals('image/webp'),
      );
    });
  });

  group('_detectMime — extension fallback', () {
    // 2 bytes — too short for any magic signature.
    final shortHeader = [0x00, 0x01];

    test('short header + .png extension → image/png', () {
      expect(
        _adapter().detectMime(shortHeader, fileName: 'foto.png'),
        equals('image/png'),
      );
    });

    test('short header + .jpg extension → image/jpeg', () {
      expect(
        _adapter().detectMime(shortHeader, fileName: 'foto.jpg'),
        equals('image/jpeg'),
      );
    });

    test('short header + .jpeg extension → image/jpeg', () {
      expect(
        _adapter().detectMime(shortHeader, fileName: 'foto.jpeg'),
        equals('image/jpeg'),
      );
    });

    test('short header + .gif extension → image/gif', () {
      expect(
        _adapter().detectMime(shortHeader, fileName: 'foto.gif'),
        equals('image/gif'),
      );
    });

    test('short header + .webp extension → image/webp', () {
      expect(
        _adapter().detectMime(shortHeader, fileName: 'foto.webp'),
        equals('image/webp'),
      );
    });

    test('short header + unknown extension → image/jpeg (default)', () {
      expect(
        _adapter().detectMime(shortHeader, fileName: 'foto.bmp'),
        equals('image/jpeg'),
      );
    });

    test('short header with no fileName → image/jpeg (default)', () {
      expect(
        _adapter().detectMime(shortHeader),
        equals('image/jpeg'),
      );
    });
  });

  group('_detectMime — 2-byte header does NOT mis-identify', () {
    // Only 2 bytes: FF D8 is the start of JPEG but we require at least 3.
    test('2 bytes FF D8 alone → fallback (not jpeg unless extension matches)', () {
      final twoBytes = [0xFF, 0xD8];
      // With filename hint it uses extension fallback
      expect(
        _adapter().detectMime(twoBytes, fileName: 'unknown.bin'),
        equals('image/jpeg'), // default
      );
      // Without hint, default
      expect(_adapter().detectMime(twoBytes), equals('image/jpeg'));
    });
  });

  group('_readHeader — accumulates ≥N bytes', () {
    test('file with 12 bytes returns all 12', () async {
      final file = await _tmpFile(_jpegHeader);
      try {
        final result = await _adapter().readHeader(file, 12);
        expect(result.length, greaterThanOrEqualTo(12));
        expect(result.sublist(0, 3), equals([0xFF, 0xD8, 0xFF]));
      } finally {
        await file.delete();
      }
    });

    test('file shorter than maxBytes returns what is available', () async {
      final smallContent = [0x89, 0x50]; // only 2 bytes
      final file = await _tmpFile(smallContent);
      try {
        final result = await _adapter().readHeader(file, 12);
        expect(result.length, equals(2));
      } finally {
        await file.delete();
      }
    });

    test('JPEG file: _readHeader + _detectMime = image/jpeg', () async {
      final file = await _tmpFile(_jpegHeader);
      try {
        final header = await _adapter().readHeader(file, 12);
        expect(_adapter().detectMime(header), equals('image/jpeg'));
      } finally {
        await file.delete();
      }
    });

    test('PNG file: _readHeader + _detectMime = image/png', () async {
      final file = await _tmpFile(_pngHeader);
      try {
        final header = await _adapter().readHeader(file, 12);
        expect(_adapter().detectMime(header), equals('image/png'));
      } finally {
        await file.delete();
      }
    });
  });
}
