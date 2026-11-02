import 'dart:convert';
import 'dart:io';

import 'package:brotli/brotli.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Map<String, dynamic> _decodeMushafIndex(Uint8List bytes) =>
    jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;

Uint8List _decodeMushafBlock(Uint8List bytes) =>
    Uint8List.fromList(gzip.decode(bytes));

Uint8List _decodeMushafFont(Uint8List bytes) =>
    Uint8List.fromList(brotli.decode(bytes));

/// Lossless storage, independent of HTTP, device storage and downloaded SVGs.
/// Only the requested page font is decoded, on a worker isolate.
class BundledMushaf {
  BundledMushaf({AssetBundle? assets}) : assets = assets ?? rootBundle;
  final AssetBundle assets;
  static const base = 'assets/quran/mushaf';
  Future<Map<String, dynamic>>? _index;

  Future<Map<String, dynamic>> get index =>
      _index ??= _loadIndex().catchError((Object error) {
        _index = null;
        throw error;
      });

  Future<Map<String, dynamic>> _loadIndex() async {
    final bytes = await assets.load('$base/font-index.qgz');
    final result = await compute(
      _decodeMushafIndex,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    if (result['version'] != 2 ||
        (result['fonts'] as List).length != 604 ||
        (result['pages'] as List).length != 604) {
      throw const FormatException('Incomplete bundled Mushaf');
    }
    return result;
  }

  Future<Uint8List> _read(String name, List spec) async {
    final bytes = await assets.load('$base/$name');
    final decoded = await compute(
      name.endsWith('.qbr') ? _decodeMushafFont : _decodeMushafBlock,
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    if (decoded.length != spec[0] ||
        sha256.convert(decoded).toString() != spec[1]) {
      throw const FormatException('Bundled Mushaf integrity check failed');
    }
    return decoded;
  }

  Future<Uint8List> font(int page) async {
    RangeError.checkValueInInterval(page, 1, 604, 'page');
    final data = await index;
    return _read(
      'font-${page.toString().padLeft(3, '0')}.qbr',
      (data['fonts'] as List)[page - 1] as List,
    );
  }

  Future<List<List<dynamic>>> page(int page) async {
    RangeError.checkValueInInterval(page, 1, 604, 'page');
    final data = await index;
    final bytes = await _read(
      'page-${page.toString().padLeft(3, '0')}.qgz',
      (data['pages'] as List)[page - 1] as List,
    );
    return (jsonDecode(utf8.decode(bytes)) as List).cast<List<dynamic>>();
  }
}
