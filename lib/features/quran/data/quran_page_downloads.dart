import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'quran_repository.dart';

enum QuranPageDownloadState { queued, downloading, paused, failed, complete }

/// The expected Git object ID is pinned to an immutable upstream release.
/// Both that upstream identity and a local SHA-256 are checked on every read.
class QuranPageAssetSpec {
  const QuranPageAssetSpec({
    required this.page,
    required this.svgLength,
    required this.svgBlob,
    required this.jsonLength,
    required this.jsonBlob,
  });
  final int page, svgLength, jsonLength;
  final String svgBlob, jsonBlob;
  int get bytes => svgLength + jsonLength;
}

class QuranPageDownload {
  QuranPageDownload(this.page, {this.state = QuranPageDownloadState.queued});
  final int page;
  QuranPageDownloadState state;
  int received = 0;
  String? error, svgSha256, jsonSha256;
  Map<String, dynamic> toJson() => {
    'page': page,
    'state': state.name,
    'svgSha256': svgSha256,
    'jsonSha256': jsonSha256,
  };
}

/// Actual unmodified Madani artwork and its independent ayah hit layer.
class QuranOfflinePageData {
  QuranOfflinePageData({
    required this.page,
    required this.svg,
    required this.viewBox,
    required this.regions,
  });
  final int page;
  final String svg;
  final Rect viewBox;
  final List<QuranPageHitRegion> regions;

  /// The opening spread has a much larger declared SVG box than its text.
  /// Its actual ayah bounds avoid shrinking the Fatiha to a tiny central area.
  Rect get displayBox {
    if (page > 2) return viewBox;
    var bounds = regions.first.path.getBounds();
    for (final region in regions.skip(1)) {
      bounds = bounds.expandToInclude(region.path.getBounds());
    }
    final padded = bounds.inflate(9);
    // Page 2's basmala is above the first ayah and has no ayah polygon.
    // Keep its complete line instead of cropping only to numbered ayahs.
    return page == 2
        ? Rect.fromLTRB(
            padded.left,
            padded.top > 0 ? 0 : padded.top,
            padded.right,
            padded.bottom,
          )
        : padded;
  }

  String get displaySvg {
    final box = displayBox;
    return svg.replaceFirst(
      RegExp(r'''viewBox\s*=\s*["'][^"']+["']'''),
      'viewBox="${box.left} ${box.top} ${box.width} ${box.height}"',
    );
  }

  String? verseAt(Offset point) {
    for (final region in regions.reversed) {
      if (region.path.contains(point)) return region.key;
    }
    return null;
  }

  factory QuranOfflinePageData.parse(int page, String svg, Object? metadata) {
    final match = RegExp(
      r'''<svg\b[^>]*\bviewBox\s*=\s*["']([^"']+)["']''',
    ).firstMatch(svg);
    if (match == null ||
        !svg.contains('<path') ||
        RegExp(
          r'<(?:script|image|foreignObject)\b',
          caseSensitive: false,
        ).hasMatch(svg)) {
      throw const FormatException('Invalid standalone Mushaf SVG');
    }
    final box = match.group(1)!.trim().split(RegExp(r'[\s,]+'));
    if (box.length != 4) throw const FormatException('Invalid SVG viewBox');
    final values = box.map(double.parse).toList();
    if (values.any((value) => !value.isFinite) ||
        values[2] <= 0 ||
        values[3] <= 0) {
      throw const FormatException('Invalid SVG page dimensions');
    }
    if (metadata is! List || metadata.isEmpty) {
      throw const FormatException('Missing Mushaf ayah hit regions');
    }
    final regions = <QuranPageHitRegion>[];
    for (final raw in metadata) {
      if (raw is! Map) throw const FormatException('Invalid ayah metadata');
      final surah = raw['surahNumber'], ayah = raw['ayahNumber'];
      if (surah is! int ||
          surah < 1 ||
          surah > 114 ||
          ayah is! int ||
          ayah < 1 ||
          ayah > 286 ||
          raw['polygon'] is! String) {
        throw const FormatException('Invalid ayah reference');
      }
      regions.add(QuranPageHitRegion('$surah:$ayah', raw['polygon'] as String));
    }
    return QuranOfflinePageData(
      page: page,
      svg: svg,
      viewBox: Rect.fromLTWH(values[0], values[1], values[2], values[3]),
      regions: regions,
    );
  }
}

class QuranPageHitRegion {
  QuranPageHitRegion(this.key, String polygon) : path = _parse(polygon);
  final String key;
  final Path path;

  /// Upstream uses point lists on pages 1–2, and M/L/Z multi-subpaths later.
  /// Keeping each subpath prevents an ayah covering several lines from making
  /// the intervening neighbouring ayahs tappable as the wrong verse.
  static Path _parse(String source) {
    final path = Path();
    final input = source.trim();
    if (!input.startsWith('M')) {
      final numbers = input
          .split(RegExp(r'[\s,]+'))
          .where((part) => part.isNotEmpty)
          .map(double.parse)
          .toList();
      if (numbers.length < 6 || numbers.length.isOdd) {
        throw const FormatException('Invalid ayah point list');
      }
      path.moveTo(numbers[0], numbers[1]);
      for (var i = 2; i < numbers.length; i += 2) {
        path.lineTo(numbers[i], numbers[i + 1]);
      }
      path.close();
      return path;
    }
    final tokens = RegExp(
      r'[MLZ]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?',
    ).allMatches(input).map((match) => match.group(0)!).toList();
    if (input.replaceAll(RegExp(r'[MLZ\s,0-9.eE+\-]'), '').isNotEmpty) {
      throw const FormatException('Unsupported ayah polygon command');
    }
    var i = 0;
    while (i < tokens.length) {
      final command = tokens[i++];
      if (command == 'Z') {
        path.close();
        continue;
      }
      if ((command != 'M' && command != 'L') || i + 1 >= tokens.length) {
        throw const FormatException('Invalid ayah polygon');
      }
      final x = double.parse(tokens[i++]), y = double.parse(tokens[i++]);
      if (!x.isFinite || !y.isFinite) {
        throw const FormatException('Non-finite ayah coordinate');
      }
      if (command == 'M') {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (path.getBounds().isEmpty) {
      throw const FormatException('Empty ayah polygon');
    }
    return path;
  }
}

/// Persistent page downloads are independent of the Quran Foundation session
/// fonts. Source artwork: KFGQPC, via Quran.ws quran-svg v1.1.1; SVG hit metadata:
/// CC BY 4.0. The publisher's free software/digital-use statement is reproduced at
/// https://github.com/quran-ws/quran-svg/blob/v1.1.1/LICENSE and NOTICE.md.
class QuranPageDownloads extends ChangeNotifier {
  QuranPageDownloads({
    Directory? directory,
    Dio? dio,
    Map<int, QuranPageAssetSpec>? manifest,
    this.baseUrl = sourceBase,
  }) : _directory = directory,
       manifest = manifest ?? _sourceManifest(),
       dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 40),
             ),
           );

  static final instance = QuranPageDownloads();
  static const sourceRevision = '3ff27b46cecb0c0519d77531d9c868a579d1f623';
  static const sourceBase =
      'https://raw.githubusercontent.com/quran-ws/quran-svg/'
      '$sourceRevision/mushafs/hafs/kfqc';
  final Dio dio;
  final String baseUrl;
  final Map<int, QuranPageAssetSpec> manifest;
  Directory? _directory;
  final entries = <int, QuranPageDownload>{};
  final _ready = <int>{};
  Future<void>? _initialization, _worker;
  Future<void> _writes = Future.value();
  CancelToken? _cancel;
  bool _disposed = false;
  String? error;

  bool get isActive => entries.values.any(
    (entry) =>
        entry.state == QuranPageDownloadState.queued ||
        entry.state == QuranPageDownloadState.downloading,
  );
  int get completed => _ready.length;
  int get total => entries.length;
  int get totalBytes =>
      entries.keys.fold(0, (sum, page) => sum + manifest[page]!.bytes);
  int get receivedBytes => entries.values.fold(
    0,
    (sum, entry) => sum + entry.received.clamp(0, manifest[entry.page]!.bytes),
  );
  double get progress =>
      totalBytes == 0 ? 0 : (receivedBytes / totalBytes).clamp(0, 1);
  bool hasPage(int page) => _ready.contains(page);
  bool get hasPending => entries.values.any(
    (entry) =>
        entry.state == QuranPageDownloadState.paused ||
        entry.state == QuranPageDownloadState.failed,
  );

  Future<Directory> directory() async {
    _directory ??= await getApplicationSupportDirectory().then(
      (dir) => Directory('${dir.path}/quran_page_images_v1_1_1'),
    );
    await _directory!.create(recursive: true);
    return _directory!;
  }

  String _name(int page) => page.toString().padLeft(3, '0');
  Future<File> _file(
    int page,
    String type, {
    bool partial = false,
  }) async => File(
    '${(await directory()).path}/${_name(page)}.$type${partial ? '.part' : ''}',
  );

  Future<void> initialize() =>
      _initialization ??= _read().catchError((Object exception) {
        _initialization = null;
        error = 'تعذّر فتح ملفات المصحف؛ تحقق من مساحة الجهاز';
        _emit();
        throw exception;
      });

  Future<void> _read() async {
    final file = File('${(await directory()).path}/index.json');
    if (await file.exists()) {
      try {
        final record = jsonDecode(await file.readAsString()) as Map;
        if (record['revision'] != sourceRevision) {
          throw const FormatException('Mushaf source revision mismatch');
        }
        for (final raw in record['entries'] as List) {
          try {
            final page = raw['page'] as int;
            if (!manifest.containsKey(page)) continue;
            final state = QuranPageDownloadState.values.byName(
              raw['state'] as String,
            );
            final entry =
                QuranPageDownload(
                    page,
                    state:
                        state == QuranPageDownloadState.downloading ||
                            state == QuranPageDownloadState.queued
                        ? QuranPageDownloadState.paused
                        : state,
                  )
                  ..svgSha256 = raw['svgSha256'] as String?
                  ..jsonSha256 = raw['jsonSha256'] as String?;
            entries[page] = entry;
            entry.received = await _existingBytes(page);
            if (state == QuranPageDownloadState.complete) {
              if (await _loadVerified(page) != null) {
                _ready.add(page);
                entry.received = manifest[page]!.bytes;
              } else {
                entry.state = QuranPageDownloadState.failed;
                entry.error = 'هذه الصفحة غير مكتملة؛ أعد تنزيلها';
              }
            }
          } catch (_) {
            // A bad record must not hide valid downloaded pages.
          }
        }
      } catch (_) {
        error = 'تعذّر استعادة قائمة صفحات المصحف';
      }
    }
    _emit();
  }

  Future<int> _existingBytes(int page) async {
    var total = 0;
    for (final type in ['svg', 'json']) {
      final complete = await _file(page, type);
      final partial = await _file(page, type, partial: true);
      if (await complete.exists()) {
        total += await complete.length();
      } else if (await partial.exists()) {
        total += await partial.length();
      }
    }
    return total;
  }

  Future<void> _persist() {
    final snapshot = jsonEncode({
      'revision': sourceRevision,
      'entries': entries.values.map((entry) => entry.toJson()).toList(),
    });
    _writes = _writes.catchError((Object _) {}).then((_) async {
      final file = File('${(await directory()).path}/index.json');
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      await temporary.rename(file.path);
    });
    return _writes;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  List<int> pagesForSurah(QuranRepository repo, int id) {
    final verses = repo.surahVerses(id);
    final first = verses.first.page, last = verses.last.page;
    return [for (var page = first; page <= last; page++) page];
  }

  Future<void> downloadSurah(QuranRepository repo, int id) =>
      enqueue(pagesForSurah(repo, id));
  Future<void> downloadAll() =>
      enqueue([for (var page = 1; page <= 604; page++) page]);

  Future<void> enqueue(Iterable<int> pages) async {
    await initialize();
    // A quick resume must wait until the cancelled writer has closed its
    // partial file, before setting its entry back to queued.
    if (_cancel?.isCancelled == true) await _worker;
    for (final page in pages.toSet()) {
      if (!manifest.containsKey(page)) throw ArgumentError.value(page, 'page');
      if (_ready.contains(page)) continue;
      final entry = entries.putIfAbsent(page, () => QuranPageDownload(page));
      if (entry.state == QuranPageDownloadState.downloading) continue;
      entry.state = QuranPageDownloadState.queued;
      entry.error = null;
    }
    error = null;
    await _persist();
    _emit();
    _start();
  }

  void _start() {
    if (_worker != null || _disposed) return;
    _worker = _work().whenComplete(() {
      _worker = null;
      if (!_disposed &&
          entries.values.any(
            (entry) => entry.state == QuranPageDownloadState.queued,
          )) {
        _start();
      }
    });
  }

  Future<void> _work() async {
    while (!_disposed) {
      final candidates = entries.values.where(
        (entry) => entry.state == QuranPageDownloadState.queued,
      );
      if (candidates.isEmpty) return;
      final entry = candidates.first;
      final token = CancelToken();
      _cancel = token;
      entry.state = QuranPageDownloadState.downloading;
      _emit();
      try {
        await _download(entry, 'svg', token);
        if (token.isCancelled) throw const _PageDownloadPaused();
        await _download(entry, 'json', token);
        if (token.isCancelled) throw const _PageDownloadPaused();
        final data = await _loadVerified(entry.page, requireLocalDigest: false);
        if (data == null) {
          throw const FormatException('Invalid downloaded Mushaf page');
        }
        final svg = await (await _file(entry.page, 'svg')).readAsBytes();
        final json = await (await _file(entry.page, 'json')).readAsBytes();
        entry.svgSha256 = sha256.convert(svg).toString();
        entry.jsonSha256 = sha256.convert(json).toString();
        entry.received = manifest[entry.page]!.bytes;
        entry.state = QuranPageDownloadState.complete;
        _ready.add(entry.page);
      } catch (exception) {
        if (token.isCancelled || exception is _PageDownloadPaused) {
          entry.state = QuranPageDownloadState.paused;
        } else {
          entry.state = QuranPageDownloadState.failed;
          entry.error = 'تعذّر تنزيل الصفحة ${entry.page}؛ يمكنك استكمالها';
          error = entry.error;
          for (final queued in entries.values) {
            if (queued.state == QuranPageDownloadState.queued) {
              queued.state = QuranPageDownloadState.paused;
            }
          }
        }
      } finally {
        _cancel = null;
        try {
          await _persist();
        } catch (_) {
          error = 'تعذّر حفظ حالة تنزيل المصحف؛ تحقق من مساحة الجهاز';
          for (final queued in entries.values) {
            if (queued.state == QuranPageDownloadState.queued) {
              queued.state = QuranPageDownloadState.paused;
            }
          }
        }
        _emit();
      }
    }
  }

  Future<void> _download(
    QuranPageDownload entry,
    String type,
    CancelToken token,
  ) async {
    final spec = manifest[entry.page]!;
    final length = type == 'svg' ? spec.svgLength : spec.jsonLength;
    final blob = type == 'svg' ? spec.svgBlob : spec.jsonBlob;
    final file = await _file(entry.page, type);
    if (await _matches(file, length, blob)) return;
    if (await file.exists()) await file.delete();
    final partial = await _file(entry.page, type, partial: true);
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset >= length) {
      if (await _matches(partial, length, blob)) {
        await partial.rename(file.path);
        return;
      }
      await partial.delete();
      offset = 0;
    }
    final response = await dio.get<ResponseBody>(
      '$baseUrl/$type/${_name(entry.page)}.$type',
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Accept-Encoding': 'identity',
          if (offset > 0) 'Range': 'bytes=$offset-',
        },
      ),
      cancelToken: token,
    );
    final resume = offset > 0 && response.statusCode == 206;
    if (response.statusCode == 206) {
      final range = response.headers.value('content-range');
      if (range != 'bytes $offset-${length - 1}/$length') {
        throw const FormatException('Invalid resumed Mushaf response');
      }
    } else if (response.statusCode != 200) {
      throw const FormatException('Unexpected Mushaf response');
    }
    if (!resume) offset = 0;
    final sink = partial.openWrite(
      mode: resume ? FileMode.append : FileMode.write,
    );
    final otherType = type == 'svg' ? 'json' : 'svg';
    final other = await _file(entry.page, otherType);
    final otherSize = await other.exists() ? await other.length() : 0;
    var received = offset;
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await for (final chunk in response.data!.stream) {
        if (token.isCancelled) throw const _PageDownloadPaused();
        received += chunk.length;
        if (received > length) {
          throw const FormatException('Oversized Mushaf asset');
        }
        sink.add(chunk);
        entry.received = otherSize + received;
        if (DateTime.now().difference(lastEmit).inMilliseconds >= 100) {
          _emit();
          lastEmit = DateTime.now();
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (token.isCancelled) throw const _PageDownloadPaused();
    if (!await _matches(partial, length, blob)) {
      await partial.delete();
      throw const FormatException('Mushaf asset checksum mismatch');
    }
    await partial.rename(file.path);
    entry.received = otherSize + length;
  }

  Future<bool> _matches(File file, int length, String blob) async {
    if (!await file.exists() || await file.length() != length) return false;
    final bytes = await file.readAsBytes();
    final builder = BytesBuilder(copy: false)
      ..add(utf8.encode('blob ${bytes.length}\u0000'))
      ..add(bytes);
    final actual = sha1.convert(builder.takeBytes()).toString();
    return actual == blob;
  }

  Future<QuranOfflinePageData?> _loadVerified(
    int page, {
    bool requireLocalDigest = true,
  }) async {
    final spec = manifest[page];
    if (spec == null) return null;
    final entry = entries[page];
    try {
      final svgFile = await _file(page, 'svg'),
          jsonFile = await _file(page, 'json');
      if (!await _matches(svgFile, spec.svgLength, spec.svgBlob) ||
          !await _matches(jsonFile, spec.jsonLength, spec.jsonBlob)) {
        return null;
      }
      final svg = await svgFile.readAsBytes(),
          json = await jsonFile.readAsBytes();
      if (requireLocalDigest &&
          (entry?.svgSha256 != sha256.convert(svg).toString() ||
              entry?.jsonSha256 != sha256.convert(json).toString())) {
        return null;
      }
      return QuranOfflinePageData.parse(
        page,
        utf8.decode(svg),
        jsonDecode(utf8.decode(json)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<QuranOfflinePageData?> offlinePage(int page) async {
    await initialize();
    if (!hasPage(page)) return null;
    final data = await _loadVerified(page);
    if (data == null) {
      _ready.remove(page);
      entries[page]?.state = QuranPageDownloadState.failed;
      entries[page]?.error = 'الصفحة المحفوظة تالفة؛ أعد تنزيلها';
      await _persist();
      _emit();
    }
    return data;
  }

  Future<void> pauseAll() async {
    await initialize();
    for (final entry in entries.values) {
      if (entry.state == QuranPageDownloadState.queued ||
          entry.state == QuranPageDownloadState.downloading) {
        entry.state = QuranPageDownloadState.paused;
      }
    }
    _cancel?.cancel('Paused by reader');
    _emit();
    await _worker;
    await _persist();
  }

  Future<void> resumeAll() async {
    await initialize();
    await enqueue(
      entries.values
          .where(
            (entry) =>
                entry.state == QuranPageDownloadState.paused ||
                entry.state == QuranPageDownloadState.failed,
          )
          .map((entry) => entry.page)
          .toList(),
    );
  }

  Future<void> flush() async {
    await _worker;
    await _writes;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel('Disposed');
    super.dispose();
  }
}

class _PageDownloadPaused implements Exception {
  const _PageDownloadPaused();
}

// Expected object IDs and lengths from the immutable v1.1.1 Git tree.
Map<int, QuranPageAssetSpec> _sourceManifest() {
  final result = <int, QuranPageAssetSpec>{};
  for (final line in _pageManifest.trim().split('\n')) {
    final parts = line.trim().split(' ');
    final page = int.parse(parts[0]);
    result[page] = QuranPageAssetSpec(
      page: page,
      svgLength: int.parse(parts[1]),
      svgBlob: parts[2],
      jsonLength: int.parse(parts[3]),
      jsonBlob: parts[4],
    );
  }
  return Map.unmodifiable(result);
}

const _pageManifest = '''
1 185309 38a3ee9fc4880258b2aec899e5189474219044fa 1424 7e31e76a24b4e2c56099f35d65a894307238e160
2 223381 5bacd05ccaa8352bf399c4aa77322540c007b6fc 1128 9eb3b5f17719caa27b7277728f76956a84479fc6
3 585319 9db5ffc6e5ef99b089f8c1474a0a6799d278e28b 2234 c69eb66415b55ac993cc7723413b55da24260893
4 590377 33652d115fb1df1e8807c70860fe574231f59402 1759 61a90fb27af27a6b2295cb1bb4296df0f2f8ad0d
5 524442 45a214f6af29505d5a0c103ab2054dc936c12eb1 1153 e7798f1d1a04fed34e2cd8ef3b65101e557ab208
6 615695 0e4974a3c40ca486c3d204905d108588815322e6 1756 634253c8f3fe1e432e41477bd27a5daaee642440
7 652077 1c1a87304fd560db5be0b5a4642fd548b60fe0a3 2034 e08d86fda8b22069b280ad9945c0b675b60b41e7
8 598895 952b83d1d8b15406b3068e3e2b9ff86de4a8bef6 1607 3c466e23c8ae3ef2c78286c5e06bb11f505f6ea0
9 545221 dcc0f042262c720faae23c492aa800d777c42629 746 c1ebaa79a48cbca28a28360f484cea35487dd2b2
10 601048 77fa302efc3031f65aef9bfc94f45cc861591885 1658 15e1b1807977cd9d337a5e5f774b2817beb25e4b
11 628446 87ef64bb554e23909653e061271fb580545853d4 1406 5203969ca2784aabfb5eddf06a9cfd672625327c
12 557250 0eaa33171a365193833b322f4734dfa9923a9cf1 1335 0cfb9ab99146acc627995e70c991ce21b30ca8e1
13 584976 cb7c720f0b7de85b12fb90dd3f4194db0d433d9b 905 8aca5ed0ca2a26fba4360444012eeda0736b6285
14 536655 c12df8f0c2a92275ee2c862e916fe9d87ee8fb5e 837 d4ec13da3123dd2c7c7a3297f53bec51526402d8
15 553812 34490837f0aa96f5bf7abafab81ef3dc32b40e22 1527 2e88e9ba376df59505e115230fdcdb7c292cf7de
16 525160 15f7d4fa6b44d608b8c4fead849b674528245d57 764 14a1dba0f2ff6f7fa90a0aa9476632ce169f8565
17 584138 ed36c52470c7cab28093e05109f27741ba544ac7 1633 f3749838cc0b1f6a3ec0a2699c74926a698bd9be
18 585888 f1bf48e0b86e53138d3ecc4f720f7982ed3f403b 1438 8014c3c0406686e8f84b00795c4b9e6439da9c50
19 654747 1190439fe93ea1986fb163e5c6fda77a617d798f 1487 0f4b41d531c914dd2bae1c1be9ccb2bcb9bce99d
20 602633 fd01c9c602c4e9da1b05e69e652ac0d03eb29473 1882 174d5cc35a3a6c078d28f880e0cf38a81e83fffc
21 580951 672832ee21ea6192b17fc2b1a1e15efcceb320a5 1303 c5d51deb98b2681ed677098014c9111528e5fde0
22 561348 8e78b81c6dbe628d5b9a98e608adb5a7cc303457 891 7cd39ec5cb61ac7691e4a04e2771c006df9139bd
23 577094 530249c05f524a9405e52256703d1fe4ff175ab3 1764 afe0a855d017055475a26e55de1a39e3c66d6014
24 631965 18b73ca45d5de6391094a24e8953d5c85810c34a 1803 eaca50668f416bf1976a1af6f2ac83f699fcd647
25 585501 7619bd53841154094116c60701bafd5a0c41336d 1178 42d68df58ff2191991c65ef4bf9e834ce7bc429e
26 577945 79e612849d2b5bdc2fb2c00c9683acc6518e8da6 1501 5df88592d89154faaf2a8c8077ce242256042d37
27 633148 20593392d0c21ac573bcc2a5fe45f72e0b9761c5 1088 0d4a9cf74a8c23236c0deb0088c1c3949e3186a0
28 535855 5a6330f271f702268bca585a3cc692bbd2f736c3 1014 346573750d2929f7add6b424fae1a9f70f53f160
29 576542 feec3c2d41becd8efa6266ab8d562c6e110fbac3 771 9421f6753c16e6a6ca31d22c1ad3b16bc8cf49bc
30 718207 6c438480d975a0cec5d326c0c8ed4ce7626c63aa 1221 3d85119e94fe7c2ba1fbf98b8c7a2cf9652f7276
31 497362 426d33edd692b69a46c5b284b8320bff6f7ff4fa 1142 704f87c9c9b88d728e02e2d554a57f01a7c2b93c
32 568205 188ea85398024c084259f04b584d2f7fb5d5c466 1479 2c8c88abbcc25b642b4625688d37360ef97883e0
33 633956 bc35ace84fbd9441c2ea32569b8209ac960a8fb0 1013 527f8ff471d57139c3d1e9f387e63f14c20842a3
34 572429 957517626a000b00990b4ec2eb9da58dd2d137c4 898 43b80f50b5704d9ca75a7f7e00752db4d347a209
35 640967 f566f3920927a7a899dc066aebae313d32bad798 801 1fb741d7b7c0d77e0daad9ae028ab70c4b0a0125
36 680360 ae15b3975e1c80cfa53e8eba069dff738f259a2b 1285 5622bde13178914d196591a7d91eeee232174349
37 679283 5b71d20e18a2541b9e4285af922f0eef9bf7e831 647 589d19c2d135d0a9ad505026ab430480817341f4
38 600311 670d6f82b27f1453d39f50da569b62b84b33ed0e 770 065ab0e22e36a94a83669ce1fdca77cae3947fe0
39 541473 032b2a6dbb75a56e0f10fd2897584df131a1e9f3 1471 82ee4c400bf8d302c471b2ae53d70513f35c8780
40 517116 5ddfea26169fa28b3a9759185a307b50463d529d 519 5e37e7a99eed1156a916e79fc19c12be27893a3e
41 491175 48d07671b5aa244ef35bd800ba2e749ee356bf4b 880 b84e6c033b33263129073157170071a89b57ccdc
42 618403 24b371c9bfb42055de876105fb4d9e43f3ddb35d 897 b07b90f4d9d6440195c3c3a7978acd56f562e47a
43 559539 cf62de6dde982642b2778d3ee8984d97a4a8ed7d 631 5b07700ed429a253abbeda5e1ae65cc3c759ca2e
44 600454 d5e2bc7a9f55893da2c97e4c482f45544009549c 991 4477fef822b0d52b66cfaf0b417b1a18f03fc3c5
45 570939 3695d3e6fc4ebb59c57aefcbc5bd368deeb8cca2 1020 9e25a11e5ddfa44d5333b025233610bc2c64b1a6
46 506799 0a7aea7c8ac9221ef35b004c2c7344004a20844a 1129 0bfb366142891d674245febc84b0eff7083c879e
47 591858 74566965c91497f5ca7cfa186121d92fa7990fe7 1470 a9dc5e6d431e8309f47c22ca37d9e5edf2ac0048
48 573550 95dbd770043ee78789599caa37396386ee4e7e16 132 9daa4d5cb77a916098fb36aaa9575131f4cc9cde
49 582756 34c8268cfbfc70095d159df16ba15f7d2a2bff9f 878 e5cbcb36042d45bacf867ecaf49ffb54e1c3e597
50 621122 6e0ca95c7f996667e40a551e17b2c5eb939568cd 1745 03627862d6c0ed4244549ee34d12f0c166d87347
51 578399 0bd1290ab378c966ff9de459c1eaabd1cf3a2be5 1261 aea70d54d01d6ff98484f351144bb899039565ec
52 573607 4c0fc97ad6e5c8707031419bf82de3646459611c 1439 f4ad8e31932d23bb644d875a7901771874e06eaf
53 627583 9c85488e85f24ee62681cd5386615e4682e37f91 1417 eb4e316e832a5685b10be1177912974fdc4b9e27
54 637225 3629f8a939ba16d3d006b2af4623660b0ca424ce 1589 d69d6e69ffb0a3351385968ba9954a57e5520097
55 610808 05acb1fd743d52acdda9699a2c550b00632de07b 1813 8cfd3452fa4a129b607014ff6e5956560023e8c3
56 597461 227b2098989a750a93e0270d564a6f8dade5ceab 1128 8b18bad00c732153b98499f523327723a022d93b
57 579886 c251965f0a1bb2c7a6f8a3c22fa2ab316e3c545b 1657 ad3fcc71cf864ecf0af084a1ca3ccad522f1ce9a
58 629320 847fd09a755b38e368a5ae08df2a42b4dabb981d 1665 5028c96c413f2d41cec2d7f5e5b8ba7feee5de51
59 627484 9d1bbefc890f63c2cae5b6b706b037f4bd1a0895 1328 1b92418b1dcbeab4b58c89ea1d1440f6b41ec741
60 576288 6c0c0ec4465e057e78a00544bd8174e73b077e62 1332 50e4a06a7b68276988b11c22b1f1cdef8761388e
61 586495 dce1d9bb396eb41906b85ac8c9ce965c81a7e06a 1673 c0494420e58fbd5474465fa41b6f3e7790af241e
62 621592 3f58e66a9512e555c52c77a374da8434f97e2548 1805 d7b48b420b3f1b89a3c3d6420ee64b60aae23985
63 643774 d45a194db760e506eabb5493caff6b784d4ef792 1613 95351627fe77ddc4786050b432142111024b71a7
64 581454 3d89631a4bb6d595b13a7014ede6a3822a9475f8 1488 02326643c4eea41b01c6e599ac17cb853bea5922
65 609990 86abd03b47a0545082551df71c14534d1d97ef1f 1162 7d59e09e5d8ace4b0aa41344c5a8b4beb1c6fd52
66 636129 444abc08e58609d22aa1d7651c26061ed4dde3c9 2214 0d4685924dda85d6429e4fb18643202c35dfac77
67 567206 7f174dabfc135ff63d76bd6104a605a8654b484f 1550 9f633da224ba5c2a1e758562e9a4f18b977a0374
68 610669 6aa9d69e061f729cc02edaa461cebf9dae28a103 1748 a411fa7fe26ff4614f825d3a881154f9afa5acac
69 464550 fd280c89012a1bed72062dde598050fadb18e34b 829 836479b5de0fa5786e8ca40a480384809203dd3e
70 614267 ed0c016a932af503bffaa6d6155762d1da28e29b 882 cadd0d1b406094aa56ce92af134ac7824a730024
71 621896 6a2f97d4b990ff85a031d2417a9b5cdf3418ba4d 1673 182762e73a65c06bbf5874e98f64a1a7b725c290
72 639640 5916c3026801f0498da98957ebfaea239dc23565 1639 fd44ded686aef2a06be1ce615e100627d4a6f4c8
73 648588 f6b99aad360f36ceca13e58dcff6452a595bb018 1489 4d901e93c68058ff2a37ed4f349aecbff71a2e72
74 577938 eba7c93e265bd96ccfe5e0339e130d907c8bc98b 1221 3d811f75d16b5028a9a64ae55a9cef48d32c1939
75 594046 f0d17144a60b82c78acd1c36f7462accd96278db 1720 9075831a501ed68573f7a6fc25f3ac14e6c6deb8
76 552363 d69054b2270a1a13aaef464d8198352005886ad6 1176 8da55c3364c66a0f446a838aca7937c5a400e407
77 708846 375085063711a759541a0c91703bd46f3c817585 1216 87c994b9388086e49509dbccb51d9df78ec095dd
78 618335 55e8141b9b34340e52a7c1152e146ace73188e04 1027 772b64819c21d1a0a319e66d4a99fa0ca58f3482
79 474607 4ef83df83b36098f9b246b2f90957df70c2ce86d 503 e500ba0b5ac64329901a5eef702206b22298232d
80 570463 16db413c3d7054ab1c4c29ec4edaeff8fd5495e2 928 602ba8545f71f9005b2b547ffc178bb454fa5fa1
81 479080 51d856b6e852e6589a21a9c6cb7915651087cba4 755 008e94725f3db07f5dcc4032cd42e395bb90daaf
82 536374 3980e16fe72d4265ecef3dc17095733499519b8d 522 39070f133c570f553604e425a3aef0379a542dd5
83 518184 cf4bae7916d62f7520294ff9f3323203fb36f5a0 1451 e0004831028b1b78cc384c9e8b78fddd0474f917
84 537646 a2f6bda09ffe08c51f07e70cbe952b4b11f75e91 893 32550aacc88c2d98a15ee08425f3ebc6c9515bdc
85 597124 80220c005eb59bbbda60e4b2b52470dacfc26678 1552 bcc7b8fe08b66c6a3ed0c2b229f94c7d9673c1e8
86 619892 5eeb550637ac3391350aebb99a1636f1ce519f2f 1350 02fc17fd366bee8d5df0847105c552ed0382456f
87 651149 ecd19a741295d4bbd7b48598110996ab996f3c1e 1495 fe148e9fd082f324ba4f03bb2318c3289abd23d7
88 553557 9e7c1b163aa333e43ac232b37850fc1e871b7397 1355 1abd2e52a7a749110130eb7fb848d7a2b593d6b3
89 602491 a760a503999e297df1bb6264df0890c137ff5b07 1815 d9e5a2fc0fd4cb6e1e9237ebaa962eb63571741a
90 670443 99db34ea52f1e231322113496f2701c78a9254a2 1030 ac116c4e9b37831543825ffe661111fe4c951764
91 613397 e4210f6856106ed5f53892c532655e5fb6274793 1387 6f30d60b4571f17692ec5486e3bf12c6c5b063e9
92 637861 8f5c0ee4b9da842736147acc84dfbe9fa93bdfdd 1017 ab5c74e27d563b83a410e1f41f91de02598f077c
93 508548 6be29185a47337374fb5dbd6d733bf59b49111d9 620 cb2f176f027ac5da772b4044d28c1f1e5d9fb0be
94 676770 867045257379ba869e8eb65c2878d6d02c048e5e 1421 57900181b48a42c12886046e3b7aefc75191f0ae
95 581107 61f08de51f0d64b9cf4a9d55c82c1a9b8d6986bf 767 8eee874b763bd1917d98e445d7f3c48a9cc4db4f
96 562264 b706832209960e7c50859f2b5028df77fa666bd8 1654 f35ee9ae0aca774fedc6f249e64592511541b851
97 550519 00dfe9be8e27c41179610c02663d63bb6d9a9f20 1714 9246a3250eb8b75c6c6aa5123d15fc14fcc01853
98 545251 da8935ed77c1f8b4c6fbfbdbf645e102ba3c62cf 1393 89bf9589478ccc552ddf1e80129c6bc72a1fd45d
99 566854 51b6c71ef275965277b02f89ebec46e4f2911468 1376 4703dbc4ac180b199b22bb998503ff6b09440080
100 658944 04c42949f1437ae1b0e8f6813baaf9e2a4dbe2ab 1287 c132615bf9280b21b8f43bfddd1909aa7ce01577
101 607652 8123dd8e0646451fd9a4ddb8ee3cdbf8bef6f100 1470 124f923fda17cf642421e4bc9c895d1e23c9f791
102 627798 2783faa717657d3da60515f069d31fa44c0a14f8 1533 e3ab58a2f29d8faf9bea42cf114f08217b50d24e
103 645437 8f53ec4291b282b5d61802f3e7abe1292769fd1d 1593 ec498776926b7b2421f257b8fda4e756b5bfb7f3
104 593154 d8cd9c0ba5ea43c1c200679ffb690d36a13fcf99 1667 979bd25818f594f07dbd5e51f9d59e081ee2a820
105 576965 27a237e3dbd52c3bf16ee304068433f61d35c6c3 1054 955a17961c04b8884eb36fa437abbd8d55c1c478
106 573014 cc363edf18785ea2f679f886db6898b054020fd9 507 7dd71d1d3fa7b2eacabbcecf428859c96253843f
107 632527 deb5d263098d065800558e94b9ec587fa8bd0b21 512 3b660c49d231236b7e37facd143b1375bb79835a
108 551686 d47a9d893a4f15909e97d69f79e017aa5d700b7c 763 215539b90df843e2e2d6e24df70af6086cd5855b
109 526542 0583da3affdf141c915034df5c2629d6da81f9f7 881 566f40a03320d38675f96a89b483cb78e3f0adbe
110 471690 232745f0d34a9575c3a09389cb32622ded8d6ed0 776 ead0f47984fccbb1c71564be1bb4ba1bd07f25b2
111 589620 c02773272c7cf373765560ba54f322e4e8def8d6 1416 6dda0f7136f650cecb47bb8e7a10c086fd1dc9b7
112 604618 fa547e16ef079e68c45fea463b51570c2ac855d2 1586 7869f5d00a2be26efbd618740a960124584ca210
113 545293 2b939d67ae11ed9a3a784e54bda10aa2b6bc156d 1014 6c16bb241f8b8c3d0c765109ed591f85f467bafd
114 555245 52db9b2b93f5673d83a7d8d9c382407eb3ecbf7a 1083 43916a4f877bb5baead6a816bd961261070b5b30
115 549193 27296183ddcdb7baec333a14cb2906ace58d1002 906 d95a7c28a747361b3e2a2f0bfe16ff52d02d693a
116 614833 592c20834e4c21aec7b65cd25d3707d00da21465 1010 2dfef7e67d7dcc0c6070bc7d6ab2c53ceddca4d2
117 711424 bb83448f68e1cf879c08bd0325b3419ea4e7537a 1532 cffc02f042de7341d537eff2139f2fa6db54e1bd
118 685717 3da280b44485321fcad4b896cb93baafecc8005a 1418 b7b8aaf8f44f26f2dbc2c0f7d284a0549794e029
119 598646 c3b0a5679a3a4215179e4c3e42502c9939ce93d5 1356 b11703ad208c7eeb91237b8bfd923cb88d3e240d
120 632608 111387d02415e8e9b45401507430344c2ffb04d4 1233 682f866a0d20ad9794429429b4b76cf76de1564b
121 490647 0f940be856cbf1f7dff66ba8c53cb0fcb30657cb 1325 4d4a73206f3903d7f5bed727489fd8b7f753015a
122 613698 5aedf20e4cfea048efabbc87651558f4ffa8edb7 1418 b9485a9c6f3b22a090977ff14dc5964af1133523
123 590793 72de2088dc3496da5a0aa61b588dcaf8c2630387 1135 1dd4ec93bc3ae1cd43c4efafdabbaa1124b43560
124 609900 6e9d7aaa4988dba16ad672d5922a069e6ac7f1aa 1617 8a70f9189b85319d7e3d443c2cd09b166113f2f3
125 637618 da028eaee6a3e5b7f90589221bf18a16b2131cb1 1151 8404ffd1c3bbd797495c83b1b4e8ee3ccaad78ae
126 591374 3b31ba9ca5bc8935896b3badfda0346c655f28f1 1003 99fcfcf8f26af4aae5706086b6175b750202ac6a
127 661357 e7bd8708d5e67e16bdd900e983afe13e14498db2 1489 4233343e9336d22d99d970bf8f37c74cf1e71757
128 583174 0c3fbebe4c5502f1cc8bf4038cc3340a989fdf92 1589 0c099e846bea0cc4f295d679b19d7fe68039aee9
129 585347 beb10864da23eac17c6b0dac1969f71dc12dbbcb 1959 6c4090400dce9ebf6b8cd87d3fd2208e2e3b5886
130 720737 29928f63f2d7e6f8a205f77f9732561b80adb322 1609 051f5a9d5a385b4e415b6f373e6a9b26fa6bc5b9
131 647240 6ff566e9dd4201041979968fb55099b3409399f4 1464 158bafed634cd70c2fcf06eab094e1e2da2d7a14
132 647074 041d4e54404f5a4480c1cab670d2d59e738bd9e2 1831 a527d043a59fbd9fe9b659ea4efd77a14ecac508
133 624282 5aa4995eace63ef61cc7ede126d7017560e112d5 1542 c39cd5f1f869238be3bc79df39eb715334ede459
134 596409 1410d681b08f813b10bec27fcd4ceaee4de8c685 1202 b55734adf5cbe8a676bcb7559ca1d8cdd92ef2ba
135 657632 6868a58903bef32951095a052b224717ef7c1570 1950 94df1e058eeef6d9efaad569d3910431340fff39
136 556385 c439eedd0695133e7e773944d3f85096866d7537 1071 7677615d9f5850601181a61c4d7aa96f3ee40869
137 582779 852315b371ca204ce632310ef8c1f3b6bd81d845 1644 b9b08e2f4c5ceb5f5e944b5a4800226cd87482db
138 615984 2fb1aafd7cb126d064d399324b262c20e6fafea8 1738 83647b9a7b3ac29130d01eda1db37083a52bb8f4
139 634139 ed9e099a07d69f1eac561b283f424008eaa69faa 876 e04759ec19e76fe016465f38bb7749c0b1eac643
140 634413 f4848f37daf073fb2e548d6d325eafc9ac4cf724 1381 8ad1f2f39572ef8f4da25429fbf188c1c57ea669
141 645348 6a51d17014c37768c7100237fa650ce64ec17a47 1786 be13f32862b85e429653a020eede30c5933f6cef
142 617066 261dce83519ffa938fa233e55fe8f602687baf77 1665 c7c2f2c5d0093a703231d9edf092458ce4441e25
143 620344 f22034ba74ed8c50c0ff08f351ff655333b22845 1162 9568c750938cc93ce19a4b2f91cf7e0b2a08fa36
144 563579 37f149c8980af0308f629973a03960fd9fdeb367 1157 2b1b4e138181f8ef1c1fb35212527a5760689d90
145 516951 6ff5bea749c89d9bf1215ebcea1ecec3e671d96c 1279 f4d67f64a80252d4afb75c1d34904fdf35497e21
146 549597 a47148059e29d8098925b3dd5738565dc5229ff0 1149 7ccb47171d2610ad3d024189faefe3824ed35577
147 565400 f83be46e315ef01ac7f11afb613d935a07f15572 768 f52d051ead7ffaf66ec676fadd6263027d7663ad
148 574596 cac826dfe66db4472b6ffc201a3f8bbf2aac5c71 1088 716b9da5811429edf498387b3651dfe42e8cbf90
149 585219 ab8269e34ebccfdcd115f8fca667ceda902f8fa3 1117 e6d6962d786e6e6d11139102962b13314cd18075
150 661576 9af28c0ded3ce9e0e9520255931c52edf7db0509 1565 a5039ab1fde9bd7487602667d178285a25501a13
151 588740 125219f2b28827491313ef35870b21cc29bfc760 1977 96df4946f98f088040a7aac959b59cd718fb5401
152 714984 3e54fdc9ffec675e092e83dd8b275854a2874a71 1971 b6f3685732193af923d410cce36edc64ee911db0
153 624938 80d13b9582140bb2a3351254ac0428b3bb179923 1430 3ffe2212a366016b234f0cd5e7ff01587fc354bf
154 659464 a6b5995521e15eaacda359e3b8bb9d7d53779a37 1506 93b3a68989e38da264ce1713406cd49f5b394e11
155 637532 7df6cb0afca9a5be9d95c58f7a49fbd979b673e7 1233 de5d7f1167198626d51ea83a160911595955a0c1
156 649006 c6ca95cd2a954026455d569b8619b9cc87f28b2c 1603 69d6891b533410e3199c8a440c6739ba0cf8213c
157 606872 da475938ee303c3639406be22a0e70cb1595fe40 1163 f9d453a7835fec4adb371c3059fc90076611b030
158 616841 78cc374a25403bc1e41bb69ce6a9cd920be05bd1 1759 a9a4737de19e0af6de24025cb3602ac59ee1fa43
159 559404 492d0b4ff81410c320bf5c035d9ebd8f8f8130b9 972 6f7ba95876c4d579100389d3b3f6cc4990d0e1c6
160 551108 24044bae64dfce5ee1e16c425c0a2a94c768c23e 1701 95d4fa92b6c981b7ba5d2dff961773c8f24e7a97
161 515868 a8dcb5411e655bfe5ddc3228946c58d249dd9631 1209 82f222717690c6be7d763770f8fab5892d665bdd
162 642628 7dc2e98e9380afe8f51d2fbd8f61880877260e50 1673 1f6e538251a79f258d137694dec084e245f988b8
163 600300 501db7247b61fb3558856a272330ee8829d32420 1643 6c5a033d054cdc56698d0905732aef6ede991b34
164 619765 556dc73d31d94411be00d24430b14ca50c5d5547 2858 62a2be08631d240559ca2f95ee0d7df7e1d4dad2
165 626689 773475afdd6930b3b38728283275ff2ee40fb04c 1746 b965f1e22d35ff4bee5e6fa8f5abc45caf0fa226
166 586039 e2a5fd042a70dcb4c64622a419f7a2be9980adf1 1431 3305e262de3ed41dd237e0862c901b5506709520
167 568872 6642a69442f3b07be291609162eab3bed73089fd 1282 b3bde9c8926e673c9343a744c948d88bfbfa72e6
168 568655 8328fbc8a95e82a5e4dd45c127d281fbe75dc3a9 1282 8007c19622f4109bcb6226841bc2b687c61e2819
169 615684 5847c9a54f4701384ca65e3db51f334f03579312 1212 02c0e5b717601d817fed30a868400f7b19f5006b
170 558188 1fcad70c03d73c8ca73946074fc3e176691286ee 765 8c0c32b32d6020d6191135259f3a84d835ef7f47
171 509922 c4def80493b9cdcbe7197fcdf149396dc0f9125d 663 4dc70c6893d7cf283663defcc041503daad1da23
172 616262 c55318c515e070128bc374312ae1f651a0c4fca3 1164 c971697d42890cff99726deaf9edd85ef0192dfe
173 628720 9b5dbeef914200013ad3b584c0f210415b970675 1629 f504bda33bfb011cfc39536b423565e096ce8b0c
174 659631 da5fc8f008f97c60c4d91d211817743954a5d0bf 1771 d23dabf26c88fac362674294058459854ef71577
175 612356 ad8b86e604bd51178a5da6be019a60ce6ebe80b8 1487 9841d061af9ffa74153305d864dd553e20d4f893
176 625293 697c6ee9e53438f83dff8713a35bd893d50d3500 2237 e806e4940ad95bd6d5dcfdd9fa91896269744db5
177 562306 96bd8d5703599c0d8b8b305dc6ee8d079feca148 1564 9fd9193b4b86456455b9a512b9f432cb4f7866f4
178 629027 c4b8ac08057bc7cf98301bcdb8bc57dbe64fc334 1679 9705a8d2d44c3e84a393cd02209229c5c3f5d312
179 589052 9f91cc34e6a99668c4fc0fd066c2b9ef2d966327 1798 4f6ed9c9f3f2ab51ee3e83fc3c27bcf511707b2c
180 599205 ca58daa50d9416c1447ea562e589bcde44f466e5 1818 cdbe846f0d938a18e39451b56c05e4368fe4d3e7
181 553181 4ddd6f41d2249e7f21a20a42c12ed378af657b52 1667 5c9e383e389886c65435df743b0fed8cc3c13176
182 572233 1dad08c7afde1e5933cf8b7ee64ed3bd12a7fb4e 1146 58658dd69ccbb4801802499545b7c1aad632043b
183 579197 46944c06f677c9b88fee16d5803b14f614a00d41 1516 8d3d4772ea80129047179aea5fcb0bc8ea195777
184 611251 4e85fa8e49f05e82214a3c2c51fd834fc1d926a3 1611 5779d2f56077daa28e37f1c26593a900d3242b39
185 622518 8462f900e174f2607bf8242858b1317ccd930072 1779 92e4dbb7e14d7ce0b29b4f14173654b1d183ec2f
186 635723 0d981a182d6c6efafac0093bbb6f545aa0f9d722 1344 61b269f8a60f2397e7abdb247a0b0f5e113b6a5f
187 638395 c9af346cdbd27bcce30356cc14ad5b608a4b14a6 1152 e993be3cdd81d5dcf963db331eae6640831f8629
188 585821 0a05790121002989996365341ebcd9a46cb4f5b2 1422 cdc27ce0ee89708e71f5c248ae28c55b2396b7cd
189 610849 27442b96aadf8268516a1d5fe3bdc6a457043e9e 1397 538f818cd67d3afa95fb93279cb35d93b01f43d5
190 566791 523f173e2c0ba5a711ca16d3ca1dc4750b752dab 1342 eb77684477fcfce51d5259da2ce9e6559f8a59ff
191 521937 5e688a61dfbf86ed9eea748add9ee272b45fb60a 1155 4a76b47be2e73c022b17b4def91b7a0c5fe450b5
192 552415 20d55d1c2825999768845937b6bd511aa03c4c91 1120 df1fe5cad6598528a6207f131a25c1272bdcb56d
193 542035 affb0d2d982069084aea9a9ea6cbcdf830470324 777 e371ee12ebe20333151811cd79f35718a36730fe
194 568192 a9ab3bbb7fc047309756e5794ac5672c3eb61f89 1298 e18bc75e18e2c8a5b0c62dc632ab385f61ce871d
195 540104 01821a7815371e38582a0fe61386ccfd99c60082 1560 4dfb1bcc737480a1260822f80315a5d465b8d74c
196 600230 ad1d2ae88a22f99c059fcb0a6c635d6757b1d72d 1452 8e1c3a17aaac479f5d6fb97b54beb1c129a5cd1c
197 567052 f58f125e46756d0d4c4596c524020296f7fa34c4 1669 294d83dc5b2a488cb2c087cc6e1bca6c01accc6d
198 556428 aa188dc06167ee49a0a7e4595a20928fd1320a0b 751 b345ebaaf0bfce7211ea8ab1eccaa46df470d790
199 579125 7b5cbd8821eee706df5f2e84c99cf93ecc01f81c 1416 ac251e85488fe29836cb1d8faa75dbf6b2044560
200 635318 38fbdc511bcf0fcbdef41a6e2dc26ab031b3d35a 1462 6736b1802b85176fc54bb65c5e67ad8c96691e44
201 565518 080267bfd9c2419e412f085e4d6d8a91bad1deae 1413 86c4e8988229fdd0af4a45a96aef7372aac44599
202 574869 1369aec888847bef827e6e99fe9a67a55e5b9fcd 1266 de81dd811c50e7d2961dc26624ca05e3be39764e
203 634057 6f5e57136baf145402317978778971ae7c08f77b 1541 f73545ad9e26a2dbb23d909680e7039ba1c3d260
204 601432 34e51cc3beb084ea15df21304bb3e35bc77bb608 1037 41396990d1c04b2379e0c99cf5421564f0cab9a6
205 535026 ad93fa3fc3045667564ddcc89df7c8dcffc997fc 1303 cc90d449838e64a22267ccab18bc2c002a44dc59
206 593295 1271eb8bcdb16effe64f05f3bf03f2a3339ca22e 994 f5c250631aefcd22258b037d84d059374352e049
207 538471 19bfb3e5b294b0cb4bad6cfe14c3b770b664e0bd 1539 f073a96dc8418883ff4c8577d59ea9ca3156048d
208 605401 7ff08cd5a541eb8c67d53c614f34b6e8acfed3c4 1108 0e81390946c775a8839cb929d8f5102cdf20bdb1
209 590403 ede085354ac5cf0570d0741979c0789a44a8e28d 1859 76feb8087db1d571a3b7dc741cf268d4b386a490
210 565066 54a1e56311f96d377ba82e79b4ea8eef218fe946 1165 0f1600cbb8a2157f44b4b454a82b447590a344e7
211 659406 26f9f82e3052dcffc02af6c16f95c3410224bed0 889 a236af3580ae8ebeab714bce490566ba91f006b8
212 666441 d9a6c590d11a164ef267abc7a149d76531febac0 1704 a1a3c0418f2427039c9308a6539d91c6ed340b27
213 682088 b28725e88faaba322835c6617e54488a896bd0ef 1733 d017bd9ec4969cee20d78abb8cd6850280cd5284
214 680908 c02c6bfc5a2e7e17762cc5670a8802c26ee7a378 2069 07f02ed933599fa57f54069dffa60458df5deb5b
215 616051 59e4a28872a60affb10ed71d07cfe692df2b986b 1646 7502fe051c3283c0ae8b2f68820b35155f54dee6
216 557509 39a0aceef1731cf9becad5ada97ce067981d82da 1839 2c8b541db5b4e9756ba14783edf8e91719451b23
217 663027 cf11e6ba8d7674aa7e17d44da69aadd55fed932b 1456 34116505ba8592399c5b02ed2769e9f6747d13bc
218 638232 19639f7e16acbcff54f7c22607bf3a6d1c9039b6 1921 66865f072fb5d3256c442d78f415b284042286da
219 618900 54e13bd3e6639b6d7a539933d339ceff6476f350 1605 928b874d4ff2120b837d2e2d33ad9dad11fd0251
220 628547 678f468be41a9e4c19cf5e7bd03ac9c22651ab16 1767 c4f9db4a7ed99963ed57b57e28d16cf886462dfd
221 596143 bd1694920deb420b736f99dc1237fe8b04da165b 1482 1a341b3cd0dd1b0414a0df8617f65cfa6c98d3df
222 606797 87803143c554dd7c1012eb2ebff4e15afc19fab0 1422 db96fd5b28f4225d13f2209e593590bed0b7fe86
223 610620 d739d07ecd6aadd7d4f41bfc9117338905203cd1 1412 deb386bb625f16b4cec69a7bea84607d34d5e74b
224 610449 701cb9967d287d6bc8ec3c6689383a68e4478d9f 1557 69c747ff3890c646b573f79dc2b910d86b949720
225 640456 b20697a9fba2c9432e629902cd47fc50210bb47c 1875 f5fa63cba4545fc0cad7c7bca35d9e299661e0c0
226 594052 ee228342f391a57e3d319665e6f61bea8d3cf0ce 1543 2348fc295a6a33390c851cd1f81c486db062760d
227 608479 4dabdf098d606313bf4d917dcda12df7a8ab7f14 1538 555815ad90a2d221c1dcba08470a995f9eb382d5
228 681027 fc0359bcbf4e3f19dc3699a78d9fbb386d4dbc37 1674 22f8d690139313d5bb9aa02a60aa683c4ee65279
229 595746 c29f60875e2ffe00961f1d01a8cdccedf9b5269a 1901 940e6ab8298b4459341683c15bd6d514bbf2245f
230 667597 305ceacfe56886dc653b6095d05777a0fbf33621 1828 8c6e0bdf9cc68085ec3a952364e1f4ecca0c5b71
231 577716 dfe150681c9a903faf90a9e93029e57d44974909 1572 638bcc5a4d69a283237e280c3ef995ed2fccb90c
232 593401 7112fb7821d510c4f9de1e77103d15877ffec941 1846 c7c4b7b822c146c7d9a1e2f2e17790741c71a014
233 649008 9c1318abb44dfa9a45adb691172ef92e60cdfe77 2053 fda38bcabea712ec1228f57497a29791db02c83b
234 613865 2a55e725df2cb3460715d3a83eec9c5e745f5682 1675 69cdba6cff599e43b1adc249e21065a7f891f94b
235 599473 cedc33804d08babffd0fbe8ce8e038b3ac43f6ae 1831 bf9f819375bcdcb6e01709cc47133e7c73167c32
236 629195 5159272edb247e117cb163300be1d9f4f1f0e563 2037 ebb7cb3de1ddaf4381c7aec48a40fec41dfcbc1b
237 601445 09951c7e3ab9bbd2d9f20dd935a73342254e3b03 1766 47554dae98b0921a29701f4e512d912a3bf39216
238 582532 5b82b6cbcab8fec7e42c35ee29fce924d6a38dc4 1659 f07110935982e6f04c6f42221ba757305a4e66c6
239 665610 c74d7e58a4b331bb3a05720e74569d0ed583dd72 1528 b76874acb7970bb5f156a832ee779d0190179dea
240 595550 2b50691686c3547e384dc966724325472797ee68 1167 2613e25027c7b053534e83c723f2106690c754ff
241 642511 97c5c84910e7fb780f74e58766079a8696bf7e1e 1824 d91f273d5832f6e7bfe6effad1ad3b786a54fd6d
242 634957 73bca98c25481928ab1516e796940442c10e8346 2114 ea7c41efb1691af7a9373700fd1e6523f5f2d9c3
243 585465 3eae97b935624f051b9136b6c430b702e0de62b1 1388 58b67a0b0d1c8d40ce991874444b9d44e8645c6a
244 586281 765ff2afb6e191d9236a260cd3f0e48ec1bf18bf 1718 e325125a5c9ab6460378d5c7c051694b983a7e38
245 578997 3ea0a725f589df06cb89c9b636fa8435915a8ed6 1561 c44d3682983d7d504a6652510ef2dc0aa1cfa772
246 589796 340edb6806bd5bd4fc24ef5f17ad7bb0409e013d 1782 0f0444b721043ae30a31a70f377e94d3acb2bf0c
247 607040 1041b8efa3e0f758ba62af1a9815075d32664d93 1725 54953016f09d86d71f8a0f88062eca29cf76d223
248 597299 dafb5c6fd3c13fb1aa88ca0a369b4fac10cac85e 1517 07ce6c895f603d12eea3361a39ae3490624e0e39
249 578610 420366d8c94e538bb2f19ba86fc6a617bcf7eb09 1127 3d1b7b8e3233dd3a449dd111c2722036e3a29527
250 593300 fe8e02aacaff5cb2d16a11c1a304556518f9b295 1730 1eb3de83917a47de440e98448dc39e3670eefc86
251 688698 a19962505b28374d04ca64cb31efb5b63afe7cc6 1085 386b09d50599ea6787c8d4a7a503ffb338ae4a66
252 720242 b8a4a5c15d74bf10fdda9f0c0ec4c3112ca1640a 2011 e650e41b4eb0e35568d3e1d4aa80954a46144fb2
253 647338 12595e464100da8a2179d064e04dc8f5ea527292 1267 e3771f16da7174999595b0d62ef2bbab5de64e9a
254 643146 820ed5645c531197f6a3d306de461ecc10a4ba9d 1600 716a0c0e0d668febbf77e9d2943601857a685e8d
255 486586 a18b8ee609a59d0e251b9f3a9e5167e242e04510 1140 60411c80622ce02273c8efbe8acc447336ff7115
256 563103 99fccd62a4c39c38fc970af38a0a0c5f75b1b8ad 981 de3437049e46a7cf6f091a543de00610b375b7bb
257 575442 465ae81c706927547b29c8d3155d891c4b40d72c 1482 ec4eb55769c8660b8b97c85a048d76909792bf8f
258 569387 fc55eb2a2b54c50b0d522434e3a74dd6ef6eee36 1209 bb78463f5798780354dc5c428914e99e6d859960
259 605207 d1b2558b920e15532601823b93c5c4aabc4288c8 1987 a13225917d810a074acc2517d3b34095ef592e45
260 586441 fed2fa73ac0d71d5eaea7aa3228338e66fb87144 1887 a313d4a7e687d95c46d31672836130debe006c22
261 576286 02c6d6dece9e71926b0025d99c5c2d68fe2ef836 2119 f491655fa9d1cb1640fc05af0c27e819abc0d683
262 595306 768bbafdd5648477e4175b858783590680e2049e 2590 5a5c249180fcb727c6abba0211eb7da42083f570
263 658286 9fda92f36c3307b00f2e9bd188f8a06a7b3ffd72 2844 39574fc262e9720fdb0105b6898cdd930949df85
264 637076 dc7b846c40f4b09835081efaa3622fbc6c82cfd4 3205 b6e1b6829c7e5eaf693e00a7cec75dffac4df16a
265 643704 90df832f75d039de8940a64a5645727a99a3d564 3281 b656cbf44924c8ad8ce6c1cef7df4b76482d4768
266 669742 455e9ee5622b0c9f90d16ef250c1cd2b228480ed 3354 380493b75833196874a029124a13b2051c2a2054
267 580044 dcf9e4f4d7f2e8d126bbc0043403144a0ac2df76 2556 d9e71c2a10fad266c77f9a0fae09d9648d64311f
268 542666 8ac9ea335eefae116760f1402f68a4faa08d3e68 1477 8e9be25e98ed6c9e0b13f9985995412bcda3c2ae
269 602936 391fbc9ebfbafc5773f5580e04b010fb9f78953f 2277 17d6fe5a364b2ae3046563834ede2438adaedc64
270 652303 26a139e6ed3dea48df1cf795eaa6697954831743 1478 b3c8327a257854705ef47f109f384d7e7ea69dde
271 584790 29c34ab7e960bacefdfef79b3b400f53218fd65b 1445 00e9291ed4d4ced0be0e2335fea88bd2a34d984d
272 669306 f6f532032a74044f6157771d70d630c6034f424b 2314 366733289d24a9d413dc6769edf63967494f40b3
273 648884 01822696a8de9706129122d0f198b1447b82e445 1909 ecc744f75a2583ce8b7b797a98093b03d0dc7e4a
274 679950 b2f914fe5ed72c077a5f4880de56a941fbbda86b 1578 02abc56c63d633505c0062f5a89304f1a414d9d2
275 579813 1dee04bed3729686ad1b38b868b07dffa41d5f56 1456 855f81b232293b89d302c5d02b062e1d243ee3be
276 574278 eed013142573aa877c52aa587d986660de2d43ac 1566 ce7adf4e7135a361328c76861cd1c807857df29d
277 582034 c923b1f187c28734c911c7f18096f1b96ecb9537 1134 a5bf1aed14460c455dd34ea637fbbb837cb21983
278 601237 e755327fd23a05fa54c632e707bafdb1c15f10e3 1827 ae4f204ea26ef5251ec88d9ae40dcd4c41b8e6fb
279 543565 bbe4bd9e90b4dab07648cbbe3dd8aecf8ddc8909 1367 946a618b7ba2ab66052bb670c35214722605186f
280 587089 55f03f92489ffc39b7269af2a827ae94ab400081 1699 5e2c831aa0b0d80a8bafeaabb0a6b45c961e2c26
281 622881 d5ccaf8a1812fdfd1fcd5056fb8940c78d0f50d2 1792 8a50623d7780b112e09d92ad8b6e363ee34c1878
282 553578 5cce0c53a68b4305f501459de9af9a21a239356b 1313 3a80daf2dab6f6f51c16c13a48513bf73754c4de
283 666160 1f3e0d0895eb2e20de9275f13874a0182804afe6 1783 4933eedda250c6d3ccc2b3b5512d224970e0fe0c
284 626652 f6c3bd9ff940fafa665434a9e1c009d166b77fa0 2184 bb457105729a8e4bb9aa07b5232d558ae3e95d0b
285 666193 8f9ff428f9336154659925c0af6ab7480f94b7be 2244 1cb2c27c3e0275160b16a4b9f3664649953dd741
286 718077 1bb215f7cfb7403cef769b538449ff5dbe543aad 2009 788671f834408a9ff76a5f2de492fece9f5c8863
287 629094 aad5a9181daf2935052d168e6c46bcd49889294b 1934 4bb5a0b601973224828a035e448379b1981d7523
288 601929 5495e5d255993356d907c0343445ad34aa866c46 1709 47343d374cd5756fe089030242780affb15aea2e
289 601998 0e73c1f185eefe961c6299d6cf0f96ba3306759a 2049 ee77417447813c142a9852a27fe53878b1a65ec1
290 618623 b8104016bd29901ac9222c8ce8ec5b20a5545409 2176 3a4b0860bfcdc5d6aafa8f708e4f7edbe42f6165
291 610687 c33cfa0f267474729198ddb9463ba3c17e88dd04 2036 8d94083141a5dd99ba0b581a68cd50196129a78b
292 629700 0c1680a8057e45a3e29052022335301862ff26cd 1654 98696c5536f29cd182abeb3fdbad45f43ddab3b6
293 648005 9fcf6f73ed07c9241b1f2cd56bbc9144145f1a8c 1841 702cf47cc12d68cc2412857c22938a533104956e
294 612356 666956f48655238cbf2359bc1cfa80bc2950fa0c 1933 dd96bd98e041da4c67a08fc9a68faa48c1785962
295 603591 f7df7a251aec294a2a6afbcbc853d862cf2208c5 1045 1fc693356ad0b870ddfc86788b475d808cb899c0
296 615876 5a5a558e5c0ad6e6093cbf7a3587458ea1c6a40e 1389 e59b0d9d1e23751dc6e6e8c01cb5c3b098728dde
297 631875 bf004f8a9f1076262232127855cc48df7ac76fe9 1549 3f45343305dfaec2b5b5e73a54aa38e3987cf670
298 664845 297a74a09fdd159a4af038e18d1df285c9fcc5c8 2178 3af59b93f1181bbebfb2d669e08f91b5af2eef82
299 642445 c204f76f2ac6d41cf30f080a8b6f413e54fbbe3a 1725 a5333312e7af95a24efb0f5894a1279279e9ea2e
300 601948 b33a84c2440629608be3da94c144559c8ef76603 1689 e35ac240508cb7e0993ed1b76301652235c3f1ce
301 634327 3185c938d24617ff7e7888ae57dfc0f384b51b89 2502 e554e44a1a1541c5099ffb40b07ce9f3bb7cfcaa
302 626017 98a6d90f6dad5eff528edd5b30ac471f534e8ebc 1840 1fbe8111e2e86b1f7a6e1441cb42b26371b005c8
303 684608 e2a762a31d865bdee8808c24cc5dbeb74d5579ca 2759 c99ca7f4e31de75c248de3efcdacc166a0558287
304 727944 c7e17958941e2e7680806ab9b44d48fac7b2797f 2438 03715cb5d8e985012f781928a6cdca60343de1d9
305 514631 65f626845f8e98aa0898c5482a84e4d94749f3de 2067 9f0b09f4b0e70f75758c4c823692372f3f26bea3
306 605113 22b3a8a8b4eaf4397afba0ceba29a01941241d32 2517 2dca4bd0d8e0de14a3b1c6f8ff21dd6cfac555e5
307 637881 bb00516a0e1980c88d301b26fe53db2293310a0d 2541 92e8aa0e5096dd0bc7526c7745aaa533fd54d414
308 663399 2f73e5a5ba4da1971e4f26fe985bd24c597cf28f 2318 85cb0f2a3745492c3c15d0d0ff3f1ee48374a856
309 689353 6c4678e094df58d8eac6e135298155532c53ab0c 2471 894b2abc03d6e95c00bed5335faaef1bc2524272
310 644774 842a3c16e63861d59e37c14523f80fedb6a285e5 2293 8b3a766f519166d2ade69bbb44d41601a140f536
311 637117 d5dc56d7f744e3947e8a148e0117a3076dbe1f5e 3297 705a1cbd0922b88c72b9800119b4f554f1b6a915
312 562776 aa80bb1fe0d34dbf58ae50666478d6a00b0310ee 2625 c833cd758b30b0a241bcdaa06fafb82af6c701ea
313 662113 30af625a04a8f85a341d9963f8654cd7b63029a8 4293 3a6d78d67c02a23fba1a63b42083cfb0b382b02c
314 694130 b3447d789a6fc575b3c3d05ed7a429238e422ef5 2465 5b28cc3809427329ee14b535835f85ea4d1e05e4
315 634516 4fc4f6cbee98c718ce9b0161a52027323607803c 2489 01dad4ae2414929af3f1500ea8b7be453757d9ab
316 687554 c333f3f872fe0f5b3ac9f025d4084dd714c03ea6 2414 cdbc97aaa7943e8bd2e8fd07ca5fbf8659013915
317 624564 3769cf1474f4388057d1914695ad9f88a2afd2f0 2283 37209de409b2e9b6cb076aa9f38597c473350306
318 607947 bb34c08fc479445874f90cd8b43bc2d8eae5a62b 2217 4bf8020b784c58ff6ae853d6f85cb318cc393250
319 651427 58c45e6879f8a0223e4ff828cafc607c338bbdc0 2734 a4e4c7df7577f71da74021681aaeb8d15adea5ec
320 610706 2c47ff9cfc289e233e463df179ec3caf9faffcec 2254 bd7983a3e6d7bee3ab701975caa49a84ff33909e
321 665661 36033cbce07c785c385cc97221cd05781955dd78 1941 78c8980ab55b48488c10fbd0ec615f1555419b66
322 566887 eb299aca637b9552b4172b2634cb1d8d05c5ecde 1827 08ef6b8f17824d826bb3211727f2fad98bf0a9a2
323 656718 faf92e66946cee3f319c68ba1b194e5c62e0ec73 2472 1d6321a1eb1eeb8067761d9f23e9d4b12cc09063
324 627360 554d041e1632181575ca26a2308dfb13db042313 2262 5b3cf4caecc596e42a306aad61f3003682d1860e
325 538103 551037fa5a0336d1837acfa37e55f9b6ca4fdbad 1878 d3ede8ccbc3d3558c2e7bed6b2c0e06f8259359b
326 615814 312d5a52a838f8aee1d640cdbe93f88849ae631b 2428 7f1edc15b0e36624461f40b96db028312c250614
327 600483 6db4542125667e7439b233a81009e62b4d30546f 2683 ebf2a9e9880aa48d6d6fa63ca6eab1838d402e68
328 598042 bcd8016651d09e6273c982b84b85e5ecd16c359a 1739 5171a2aafcda345d29b1ae45da52149cb3d8efa2
329 542864 69cf6cb354e7f8c39c40277f8ef7cd6dce4b3cdf 1491 f271a935628d60506ee5960553f85c7bb25ca965
330 512677 6ebd3687a9a00777605f086adae9f4b7ea9f5d92 1997 aa88944c3894a2046b96a74e39d35c2c3dcf741e
331 528208 4359673788dbaae7a67736d39894a62cc543e3b0 2110 7c56a1656a3fb95ad181e83dee6ce020550a41cd
332 565220 de33fa0b2b4eb06c5e44bd497a58c56b68a54363 848 ab5ac41db2252b18f700f818863f92f1fe7690ed
333 642837 17d379539307fbea6b7ce624296d21c642111805 2021 dc3718cc3bf8db58156c99135f057516e0c20575
334 607524 581e8c16a534df7dc07a6b4fd0ecec1b40994d3e 1616 4e74d5d90e977eae9cb2860636a75dd95b36a316
335 571003 4b216b75f6771c3a7d551c70702d744cb2e78c81 1247 eff368b6a99cafe3fee674c30b13ca44ebd2be38
336 662037 91bc3972806364948eaee3f7d8115c8e80056258 1657 8fcd07b7cad966a42f063f0c8c5def8442fc90a3
337 618059 bc3ebd12c7dd90fd296c0e962facb77ab8917e98 1717 a0af464b1f0d6002388179c79c06e65d5df28e6b
338 642291 a84efae1baf73014b79b4f1d9dd96001447d8fcc 1834 f3f5a7dacfff07dee35d24d9b31b7506170ffae0
339 554809 0c8c0e6e82c7b9ed0b4ee8fe206d11ee0f037445 2001 95a1f018144b59a078383872d5ec0d7ac54a74e3
340 600163 937c21903f2945181d7fcb7bf449b66fffe9b2af 1459 a57b1a2774daba8dacc42a41f2417b87eecbf539
341 546388 558425d2c45a8387d85ae01df947c603616428f8 1065 7a15a2d03401042de76328da1cb39191a6606ac0
342 618669 b5d8da2369d4488c825db4744a44da833e41c25f 2841 7391f9fb2eb5f0dedcfe3903ae579a111d4d750a
343 660006 9b83580e20392373913055d38c344dbe7c072212 1810 8e75060a7adc042793eb9afd8b79f7777fe71309
344 699680 001715b4e259f61308cbb0823f88c8bf6d2ce309 2643 841fd39e7e2436f76ae9b55d6e9ed39693bf29ed
345 697422 0ebfb778f29432d9f10dcb829e86fd8ceb0e8d37 2949 58990beaabaa0efe6bdda64f469dec1c3296f42c
346 682867 e30e159029d13b9ae2d6f6de1aa9c0ce570c4ee4 2641 adaf68a159313ee3f0bc9bb6d971a6e844393cd7
347 620000 06efb5536bc7fd24d49d0388b23541f4239746c9 2889 476f238dee6c28e26852b7080d284312c2db6d2a
348 627768 34c6309459edc43ccfcc7a231cd028901b0e66de 2574 69b95a9c4e7b63e80660b0b0fd09b3bcd038e994
349 608593 5c47a49a6d0da404ac3409c69192701117afecad 2188 cbbc0d02f0bb054d6c7fbae4d77d63bac0a5e87e
350 719689 f94215765f5ef65f7e554301e60347bc1b8ca44d 1946 78caf77edf28c4265fc5d5c1cfc2f14a1a843e68
351 708802 3d268edc31046ba534c00fe3805667a1f5de0722 2076 6deb900785d617b952707d1d1a242d327f7169c3
352 671034 e3ce0202a74bcc40f96c046017ca8fd077b76199 1559 bfa686df3110c2dd5275fb53f8894ed2b09b10ed
353 606716 ed3e5992e4039cc7a6c2920d9d070f7fbc299ead 786 48546a08165eda5c81b76c536ea78e0cf5173cb9
354 688192 a25fcb4a26b9f48944f8140105a7deb6b3bdfaac 909 537e20e3531807e3527629e22b3005f1925c08e9
355 669086 60488b26d2e654789760e474ed2ba3ff213cf7af 1364 f67790d0f03adb9390ecf3185096f9f399b7629c
356 714109 d1cf8bc0f2465b3778e19b31ab695cb046ffb1d1 1951 bbb4d86f31648373ae5913ef08ed94df109d3ce2
357 640677 53ed8feeeb147fbb895d2a91fee82e9d7e1814a8 976 612fb4c56430cdd9b6bd38ded0400dffb4dc8598
358 545652 e59db770e0ae5f74a40b67b1d88d89efdc8b28d3 644 870b0a721f55aef933ffdb92fc4fafe40959f3e0
359 580063 d677d7c7739b3ac02ad00528be928c7dea544ed6 892 09d237047bdad185aa2973c70ff9427ab8aa27cf
360 580071 6e165433be69624011a48679cf8142b1dda3a3a0 1817 7e5f465ec8c8dfff6fc15af8911cc0afb674ad32
361 576011 7e1f8b33a0293691c275710f4ff21f49dc983c67 1496 95e902abb771334dc2df7d28e91e5f07661dfc40
362 637281 0ab1ad0a9021961188e25a16b0862cc83ad24662 2365 bdcfebae29dc4c178a5ab53238e232896a9f008c
363 595428 86472d64d4e67c74164c6f993b626f932fb7d6b7 2195 8dc891269374767d64c041f01efd50d70822f6d1
364 617526 c7293fe2ab7d945372cdad0bd6ad87133752f11a 2446 788cf78d275321680c9a13dff21d77c69568f500
365 603470 39fc55e6689600e39dcd0fe3198c2a7cdb871eca 2417 5ebb32b09001b3677eaa4e41fe3d7d8b949738f0
366 545542 66ded6ddf43641c8f4ee92f75349653323b6be18 1896 62c3558f7ac15ffa79ad2d98650917dc9b63c8ad
367 688393 3415387892204d0309f94787428043850af86f96 3228 1c31753afce8fa910fc5d2ab155c0ddc42fbd4a1
368 692853 cca5f9adfef03b183bef5ea7c6b405181d705e9f 3172 2b7b89a2fa2b43329335bc022543d565cd2ad005
369 733602 12d38687841a21c68530c3c93798ed265f9718a6 3379 a047c20144efe65010d244e3e77b1d806c87efcc
370 678028 023a6d1f2f8f4d5533ffaa873fbde927d66caf7a 3724 0dca7f8ed6491252d3c711b46059d127509fec83
371 743333 09a79fbac2ddf1f4f4fe63deda8e409be4d81c4a 4627 aa5cd06b3e61be9e96ae8d98c2431bbef77c313f
372 722811 bef6167e8b57c3f9090019451c7d53b90a8e8271 4010 e8e756d0732f97b04d1c43b1e9dbbd3a37711762
373 713909 3c71ec41bfa39380c63042239ff7b08aa9673228 3737 273efacaa2b5171edd3b2773e869f84b1998dde6
374 739489 09169e9c3f40cb5cad9b4cd060d4fd579d350c1d 3925 bdd7e0a0709877ca4d3449e671b8a074ad29238a
375 694338 5acb1a420dbbd06b78628b2740ba1d7a6afe4f71 3961 773a5a809242f6ee71c25c9c84dd922e14730958
376 638590 146621d86ac19922a897cb782b2b79d84ab89501 3321 081c2c93234aee3f5ae50b18cc450b3155d66f45
377 695953 efde8375b60a3a7d82a13c18531201a92bd5aaf6 2416 d733e35fd5a2254bf1f6c99c8619d24bb79d1daa
378 629870 6ca19ca544f00898276c1d57455c39d1d90d0c0b 1731 e2e1d4b4d236101b0bd56b987f4fb0133f94dc54
379 665190 b0159ffc268f4796cfdcaff5f9478d087728b002 2506 6ba6a5385addfda376dfe561f836f3a9b1547185
380 710476 534b5f74965079c2736a40652d9eb42dc2edbb67 1834 e09f3675683e6932ea45cd45a64e9d2d1a6f203f
381 574702 fda6b04eaec5f099fe5bc9e7a9909e300af11bad 2273 bc11e1de9af607c495ef3d343a874442a40a35f0
382 587190 d0e22c008322533d74bebfb690d80cfb51557770 1567 4c921e265e9ecb72831082f7337a3abe2e4f1a8e
383 656710 5131213419c25f8d84a4263dd4dfdb4203269b02 2413 2ea434b2cfead1280eb2a5a5e0bbae15e2a47fb5
384 660736 e4067bba29c3c345687d56ca04beb613b04180a3 2366 4a81301cafb3879b93a2f629407bde73b894b315
385 578442 7faa1c344500fffefdb39fbb4c557a08d883b700 1833 6ce731baaecaf7b08b350bbb8784c51ec96cb10e
386 567332 78f90fadc661f537c4f6ada8d547c0cc1bed8a95 1308 edfdf8dc2c24b55c94af9fd3e73d46d39435afed
387 660113 40b9b14f46e465b383353dd10c695081c62560bc 1686 5e1ccc1fa3dd55513136cd91fe9910b361a7d191
388 584723 a07a8bf8f63c3db5e70ff5d5c34f044a48220be3 1488 b6cc37b7ba06896879d5001c587ded8e022f8cd9
389 581831 78d39f9b329e7ea096e017bf0e42218f52a7bbde 1347 c0a9371b6aa30712a516d7f7a3c249776934b928
390 558685 4a5a654b94708c3df3d5ce40b04f47cc0044deea 1367 5a70523cb7eb8e8528831578f526a531e5383b32
391 581386 eba2433014d61727b69672b944409a0511b113d0 1404 ca8a91ab90814d53686b5a034b145bfe7a5e756b
392 612621 b4284964dcb00ba2c916e2ace674b90421cc91b7 1830 c8a0c04ddb1e87915dfd0a048799c6e8380a32d9
393 640224 15a12a83212b328376855a25fdd67012321ee120 2187 568c88af3d412977a27453f2d6cb8797352f2101
394 602201 2d7c75161b5108a1b348fc5d15d1f5a39f764b4a 1490 8de862e75ce808af6323b39f430087a02c7637f9
395 610343 9a45d103ead8faf6439c0fe64f76015dff2bf5de 1565 ab3349386ad5193eab02917597ccf3447a3aac05
396 572913 347bea17460b6c33b7ebd2ce7ac1c41c711876b5 1967 828486656a4f76f593567bd260106c67ea55fdac
397 603072 b57a282139119b6aefeb4e9bc7c623ac7116b5c0 1281 e5cfdcd4adc25e8c799158e8ab015045a882eadd
398 596969 e2d3075df574db2af3c17ee36f5938495346c309 1908 ba96909a5ab78606543036e0d8ddf34cd5d4cafd
399 561818 06f6450a3701bf8d5cfa6dff1e03d6f4d97e8862 1346 caf0addf99ad91cc952c0f8391b64c75e17e70db
400 545634 53d1c56e9ee8c33ced7222c66b1750a724bdbdaa 1405 e4827c42074112b701138b1bc652ac6d4fdae2b3
401 547877 36d206f4d9fb9d20f3a951b70c13e65d2327f5d9 1353 b434a6381c7c70b576920eca83cc504075a10390
402 585806 d26a849530e23f9e5f4d8d9798b7dccb7763d29c 1459 44ed186c108aa29ee4fc403bb63e174e3161cd8b
403 669257 0b160c766bb142bfe1ee74f9758021e78e9142aa 2117 bf4d3e6bb6cf0fa8cbc9b812a808213f08e0387e
404 553137 910780833837353c609e57f8a3e72490b019118e 1852 312f9dc3d424d298f01c421433d8c9663a9e928a
405 620343 fb40608286657e36030482e90d2412c93fe105e0 1870 0dda5638eba809cea8145d3d1f4b04aba283d2e1
406 590143 c2e148f7d71339b2cdf0491ffc3bbdc151abc6ce 1931 224dfb2d40cfb4fbe97a897c6c3c374c2c52158c
407 593115 805094cdcc18d3513564d5368543b3b20108dd6a 1709 547ac19eb43bebadb9a177584a00ac85637a1d11
408 651808 606719073a50eb19d876e4efa4b44392267a4c4b 1844 8504a566ce248a93049f067852d2208d26672695
409 651551 e69f1082f38723ce41d4bdfbec41a8f7d02d6bbc 1701 c2823f4855633d1ee73aa6fa903736a7f889487c
410 629274 120011d55f25353eb16aa26767a5365d09cacd99 1797 8df566bc1de5e7f4cfda640a0fa2dba35e290c3f
411 569874 aedf376fbf037b29eedccdc72593e1e329d96651 2014 fa691340a5addc1507b4cc539397072637b4fa54
412 627153 fee25e2f5129c33e120847564914f41fd048b541 1843 498b94c8109fdafb26ba47ddd68a4c3d1edbcf98
413 635634 dd4a9e7476fcb4db38a537b75a2bdd50ff582b9c 1868 48a117af5e53fb2787b986e5ff3d9ee8cdb3d69a
414 590138 e28c3649826a83f5ee1e20d26bd6fb77346bc0f0 1158 2d92ae9f5d36bc224a11ca5f38d281b72acf83b6
415 616686 ab878788cd5805236f4c9780d9fcc4b5add6de36 1968 0ef70f961aef19264b7496d589df96a1a68690d3
416 592375 5747bbab2560854795a0dfbb109d6c6b412f4156 1743 42eac5cb5841277f801d5840d2b0facca1855d63
417 572501 e58d8917c52423775b547bb39cf78e7cbca8978d 1706 38bb5670a72678426e551900a5b7826c01009d16
418 590855 8f288455c63830597ef6ace01f5cbb40b0409d20 1290 37c9af8c6cdf8f846a1469b4bffb507fe20ecf07
419 645103 5cbd1b76736f89145bae2a80ea4da9addf941426 1771 488dfbe5329a1f3f632792a881ae4fec131b3cfc
420 645381 21c128131f835cf48c0fa02d23cab568da3bb0ee 1478 ce9508a51f2ec8d78968d24e0e88c08155aff61c
421 604427 dfdeab603ea5363306b7389aafa2db69e73d408d 1779 e7dc930fdc01063289d73f88e07dc929fbdd5503
422 563930 be322d7cf924619775718885599b912a1dd7d0bb 1009 9e87356ff05184822aaeac05a457ffb92987678a
423 660819 2d0c5bed67c002b57427578bd9695977c63709d5 1552 a424ae66e241a5c4f695d33bf0136119b14a7b2f
424 589092 9b59474ef957032ee16226462c499da4b21e26ef 1281 b9ff727524a8c4bf339127553938f03b45dc0631
425 592295 0bd48f429d6fb401bcf201418c5fd18dfe61eea8 767 7cb25a75e119af2211fcef59b94cbdde1fb39d0e
426 636384 cd85af20632f6d9340cb2efd0a094ef77f653f39 1609 de32abd0ad09874b8e20948443180a6987329411
427 650163 8e9a59cdb8e6af82ea103c8ccdd66e7b58aafbaf 2148 5141263f5b8766b3858512232307a23e042a4d70
428 538025 189db61001ec66cac5f582dba2440171e5bfe087 1601 bf1156e4b97ef300fe128466d2215b5265c63d62
429 616688 87a4539a1b3f20e98b139e845245140e7d352ac3 1457 26f6c18b761f86a083a0b6310e630cef8217fb31
430 609250 e35f85a7e8f31ae683dc9665d6eb505bdec72e5c 1374 0d564de0f03c4d24b93c3b1eafd5b087560af3bc
431 609155 221cf535d89ef6ad5c88ebecebfd88ed9f23eb7f 1509 77cff01e6e7e7f69a198a4c27fdb479f79f71f1e
432 626771 c4ef52aa303005c4bc5aa443dee37f3074abde6c 1530 f9e68479e9a035eaa14745175551b71afc7ae32c
433 662029 4c32d962c8674bf5676a77a142c660502bafebb8 2003 47118a28e436841cbb86bcf47dc1d417aa4f8109
434 592459 ae09ebc8270d53e82e24cb68bfb8ade93f91be08 1679 64965598113656b243d7718f623cbb962317f791
435 686957 d97806ca9c9fb6eb567fa4d75267d378f5247a70 1669 a3178db96b40b57f88b27edfeac1cf156314c909
436 612918 3597faa138588a0964d90134ac3856ba7c2fe574 1328 891e8cd1acd568b408ec1d018f93396ad5df6456
437 632997 e161a74c06cf9690b352be5a8cba4247f8a307b0 2167 28fd604e07b383d9a6131587279fda39e3ef465e
438 591079 e064dbeb5740932f671ee965c1f9184613f2072f 1754 15f2ab0a27f8ca1583dff5ec6255950aed495de1
439 670878 7a3e3bea47af8263ed507870c714ec0205639926 1294 642079b52bb86dbf8a3c14a066e158202dd0a38b
440 556087 67a0867be0bd090429090e2d8aeec31bc5785d28 2328 f84bbfbaf11f5a1510e67a2716c2061a434fc7c4
441 639853 10126dc068a42398d8412be15ffceb7b9b631cac 2820 9ead1db3e6fe85249ef8db3defc1dbccd860679d
442 619238 76ab23b5ad5460fbe3cbe5e8d632c04eaeee6f9e 2494 43f71d7906a93419c796c3e2007600c90553c24b
443 652208 d2841eac1404235c5b797d2b1385cfce9fbdbcea 2651 ff31c90999871213cbc4212b15896b47a4004257
444 645473 a572ebcc01ef063ccbf867bd45198ac565dd6732 2842 b10a29f5104bc04cc83cb0a36860693a23e83553
445 585690 2f77c4f1bdf53cf63c2083f0d498d601e2a8aba8 2369 ba1086b4d40da582aadc646577559d215996fe4c
446 731638 ff96028eeb5c7a443d199adf877cde84458cbed3 3785 9516b01fa8b46e402c97ea34ba9d6333b6bdb676
447 734368 1c98edcaeaefcbb1a2b38855f68a9e3f0c007f6f 4319 7cc5e61eb4d1d52ab630236fa71d34e1de0b1cc5
448 694048 b94e7323819f40afb1d6262adb91859fa014e210 3967 91abafe324bf58431274c9e5ebf86af5264c2810
449 703367 552ca128ebea9ebb506747a35929fae62928d5a7 4052 b5f4e62471ca10591f6d2d5fa7baadba6f2f052f
450 647734 a111b6f61d676dc7f77107e4c78e3606f0b5b75a 3978 e1c2188f895878eb02b66ca67addcb31123e4b0f
451 697621 9f3c9351ed24e7220d171e215e333628279a759f 4262 b72bc1d5cf12529daf9d6c4ed457afe3c41cf17a
452 709744 76cae4c331ead860b31216f8f3a22efe656bd163 4391 0cd2fb4db6e41665b9c6d46210b5c69d1cf22749
453 680015 01cbb93c38bb5d8de742a14c08310c843ea2be71 2782 cd4c5d1ec755a9dc028ef6ca3594805e4bdc8101
454 677245 16c602c8b74d6750bde1b7edaa3fe4d176f8ce6d 1813 cc058a34c3e72abb8954bec28ecab2e43fc33789
455 698083 a0d61d1a3107bb5f2cddc33096e2d074e00f30bf 2823 23a3923c8b00ed29359a6659cac6cd712d70c912
456 701176 10344abc15f91b26bc1eed57debc79ecea2f2e7c 3153 0f80bec0280e093b78f567c2346093132d2d8d44
457 726220 06dc9d4adc2eb03d147c439c97ac5bbbc43d4238 3794 adfc45ddab0c6d72c59a65db4453836170d7afed
458 583538 880b2d8ffb96c0aca362d82884f2926aef9f36ce 1608 4d4c61a144a6ff2fb47b357a68768dc55df5b922
459 639372 55412a92c440f958688108acfc9c468f29aa5c86 917 6e28100cbd6606452d0d4d2a99f80fc7775bdcfc
460 718028 30c1f5e767c8addc31579c7f6493f2863906af59 1993 696e670b982eb02e9533df46c1e12d140ef7b89b
461 637184 1e1405a60bf7d5bfaddc648e2d4800601a2f13e6 1910 04cd3404bd76d2b4f9bb3535fa474067363886f7
462 570890 c321f7fb94bc39452ae5bbe4b150454f528fd029 1740 299c6e63d46fc1e7f6bc616c9ab0acbf8e7e801e
463 577176 405c8136bdee86515ea0563e6c8ca175183bb289 1584 19d8a939a27ea1192cc06d6ba7065d6b44b6a1f1
464 600229 804cccd2ddd7598e275e12ef30a4d7e22f900d85 1920 35907748af7d8363bd01140b7893e0669b556510
465 606850 c69ed6c6bbbe578bc3a4ffa146d642450980834b 2127 c9e51f50b08acf5da709d82efb82e895e5ad52c9
466 601038 1386fbcaa36a02d3ea2e006206b898e3f23b02af 1168 c5109e8e61e5852526a286ae77d8634471d8090b
467 556436 b6992b6f6c333e97ad8e8183c3e8ba5957312525 1517 d17eb1d8ca8edc253634c9086313e0a974275b78
468 589093 63724ac0505ad572b49929beb711cf45cdcbd6a2 1981 71ff40c15b6d53e0bb04ff69d9bc7948a39ce5b3
469 584736 8995a7220c84b725efb43a3608833561eb61f41c 1900 926aacc8b30b67fce723499b0f9ae71983814226
470 599079 b38f75947f1f4256b8025c4724417a20d3d04f7a 1546 33c21af5b865090e31872c2e940c01deb2ebfb07
471 553073 308f8d1eca30cc06dcd44c2242fe568d861c45f6 1542 cc783ec4ac7b6a6f1ff8b8d8d2ba03260d01bac5
472 581568 b99cf58953571727a98bc7d2a07326e10f870a9c 1829 1e4c0ba68618d3cad4d334e050827d9cbe16f964
473 538215 5cc375c93ad19b8b3b59442d11a9534e23d50b7d 1757 5495041c1bf98b16a35805b988e8ad820a7cfcb2
474 545888 92ea7d1f2f2b1bfd722cf4b0c3072489fe42dd8f 1590 9774a53b1e1add8ba15dbbda56f741bb7f1ad9ab
475 603440 34ebedee098016e1bd7129236d634bdce659fa03 2169 96733ef6e3fbd65f92facc4d3c20ff2969c56f6d
476 582636 e277cf4709d8c5f12a4ab4fd85b89fb7154c98ea 1692 435397fd1616b7fed201350b21e09b0f2e17266e
477 606168 2107d95b5c78e54f54080082c3d737826209f7b8 2163 4d6b6b3a5852044c26431f866f76ac1ddf94e8e6
478 652753 bb548311fe7bebad18245447603ad99b525ccc2b 1775 8fb0d19ba0fa2b218c2b9499555736383fe6cbc3
479 641643 48232ce5880a705a982ab9b7b7021b7249f83eae 1588 36fd4325520c3f50432fdbb6f5552aa3a0b372ad
480 586104 954331fb893814bf9f9ff21439166a75e113f4c2 1904 5f5a7aaf4c9cfda5aec086049c69615d855f5c75
481 648854 452bf0efbb6473844c463000b5f5f67079942117 1671 653143feeed33736951eb4d8172aa2ace771d2c9
482 625814 90dd8cf91e5c435167775e993d57b9276ab01b4e 1724 ac17a886a3f59b2a8139f4e8cc40ebb01adf2d15
483 608232 ed0ba8d93a7b5832195d3446020019cfe4d38238 1969 b7c636ea35a2458bb04a34f30ce9855c8f96fe3d
484 611257 457eabc6516dc30bf9637e5722f7a304c60eedd2 1097 ae828d1514e596d00957c92675b61c6119a47f2a
485 572507 fdb22feaa41e1e1c52927f01794b182eded4c19b 1314 9a78ffc893407d3bfd9a92db56d1888d0c6c0e96
486 657799 b86d075d454d6fa2f8c812d8b109ffc163388a5f 1812 d2226bba421880150efded50c497d54db3d8ac91
487 699995 f8fd457507cb0f45ef737a4026baf5c736c7b9f1 2578 6b7c55e8b89098f18d5fe88b85e466c2147edfcd
488 604292 6db1c5d394e682294ec6caaee80c014f581fa95b 1533 8c85a66a5a75d0c1a31ff3c1a569c4ee356ceb07
489 546021 f29c7ecaba19b9c7b046a0ddf1b1c8dca4f846f5 2137 745ea742be0037da4d458681e1e64a7196aa813d
490 618134 5c7a43ea2ec47db555b777d6c6b9fd831277f653 2415 7aac4a82897c267d4829481ce96e068c1e26dd7a
491 655896 17695200b5e72cc07c608876ac3482b401a1fbf4 1966 dc0dfcfadce295d880535a1636dbcfd26656d165
492 635015 688f5fa423f3cfde544f272a85fc641077586e26 2734 c445287e9a97c8cd221a8ea1130ae5f079f321e1
493 605997 253eee22919d8e9e6913bfd31c6b235299b2e5c2 2524 cb642d6ccbb6228f4a6f791978fa58349c82c702
494 626945 56fe5a2af7898da45c391100e986669bb07b212d 2378 0155321cad0dd59eeb746303835a725cf21283f7
495 675283 5ee6b6531f4752ed4e9d3876acd9754d0bbeca2c 2917 f5a029908098d3cb633ead65c7c2ffa902eae5cf
496 617876 dc556e5918c5fb9570ec90579f2c3ce0691701c6 2926 fb873a1b841016d7d073dbfdb5ee4296b40c7717
497 698521 d4c0a16f253bb1af1eb3c89c1a77bcde90c4bc58 3529 62474572bcbd66156e2cbc6362b3099e0a2fdbdb
498 558645 28ced42a4765de430cd46a23581b6dcba1a34263 3421 479d1c38f2465837365330e9335ff389bff97a63
499 713365 5331bf8555834ca253c578d752ae07e62fffd9ed 2432 0efba60f570b8df5a08c40b3e527afcfdc2da96e
500 631476 7b7b521a8e2855f8114ce44b326e6b69fa11d38e 1754 44f96d7b168f7c6151f67d105763a27c7e6f2727
501 720564 9f4896cecf1090850f76ccd3845d4029f5874607 2105 a6d3c6524d66f01a0d8bb7fecdd784bf145dcf7d
502 606641 1609f1539d18f40e2b08316ea37eca843fd1139e 1734 0d9b763aced4e1a51a7f16e0fdb14ecf757e91fa
503 656941 80050f707556c2681ed6600321ae29d877299df8 1984 4d3b1e00d5e2b8e016ffebaf670ca57d07026052
504 689493 51ae6c339bf3cfd7e52101d14783ba688ec302a8 1348 aef43554d129db310c7430ae2c43100651c478a0
505 638396 74cc26b117d4b5ba9d66b05b872164604388e5f1 1656 3c38ae95416cabdff2e15dc64fe659658f028587
506 598001 1c1dd5fc0f789b2e6f2143fae858fc58a5276982 1278 0a6e8567c32465badec58c3709bfa7b5f144313d
507 723645 3ed8072acd6e7cd573bdf19f84d588b339cff18a 1867 833382f4d2af7d7ad3a215dddf3cb26c748f13ca
508 716076 b84084ad87b89f1ce1c69d70bff6e142e5c3e1b9 1736 192b3fc8c12bbf38209e564a069537f50a387974
509 620617 ee8389ea3c87eea020b8496d7e5ce58d4de2f94d 1938 930645c2b256ba6b6e7dd5f97985099db95813b6
510 651708 d4bc0e9cebd8891087c9ef5c81a21bb20ef1e567 1878 fc7e2c99a53f8ba77bfd2dc37f2847cb6dc43492
511 574432 db224c10d16e098009fd23801e5c4091ceb67fde 1788 029e6a8d0b32dce9e512287f73f921f58cdd80fa
512 611254 ac328231049f7bd17703dec5292601caf8109142 1332 09b96f168055de0d2d8fc3035a3cafbd11ed2763
513 632386 fe0a198d1011bb9298c521cd3a687846f5c6b05e 1725 4cf8b2326661488cc2633693c8d2f36dea127e80
514 588835 ea70bfe734d210d33cbc5e25f72679d7009b2b5d 917 3d4da4653240fe2e9496c92fd739eed48a0be228
515 594773 93b24ce72a48addb8e5b3059b156aa254ff9231f 1022 cf2de555f5d40169375c1d3f6422c05a454c0d01
516 704716 8c7a6dd7ca94a3caf0978eda01ef7fd677cc28de 1217 133bc3524976a10f8e345a5989e30a0bbc2819fa
517 659481 6d5d0dbcb43f27e88a5cd900e79ab2638fc6ffa1 1482 35a3f9c9d01aa321e2fe089a49dd996002d843c9
518 610411 168480f91a7979dc18839e9e7c3b22c425cdcad7 2590 c4f3a9b31226511a3ecc721f264a1c9a3b61e2f9
519 740079 ddef1cec9731bc7b3848a0e0df6b8385d70778f5 3402 6e4a2d90ba35da9e8134f8b8f7c875c76b7fffb7
520 590553 52bb1f7b8da5bafa30467cf1eb8abc287e25beda 2721 714c6dc18e5df0f8e35f00bd345e9937d6f22098
521 746609 c1440c2d923f8cdb8260f2a6305813231f4729e6 3765 3d4714b7b384b405a09e98964f23a0acdf31d18a
522 710827 9e4d284dbca6cce8d604c1cadd741863f2c1c402 3593 b45972e633c66a92ded377f7e3ee3a37a61ba402
523 621656 cd8c89aed33947f0d20bff7e30ffd90d81f3a2db 3658 9010c5b55454dcfb48b3618973cedb7cdaeda585
524 688465 8b1d5c1b0a37b42730c214586c6517e583530f2a 3026 d4e0f1737c729616c831d07844a224a8686ee14b
525 680385 52788466824a3237e0b48a5dab565feabc909c7d 3097 b69c4d370755e7c565b530e08d38a756904588aa
526 710406 90db7310b7b18550815f93a19c436cf6f66ceab9 4202 440b6782e0d390c185e8dc4fd251737250467fa0
527 722418 ca8d236a6a2eadf3ee82b9377426e1a3e6d0fae6 2981 a9808b8b93137636c8501702da99821dbfb3edab
528 660003 2e1b13ba74a4854a1f8252cb3f381e0b18877885 3619 cf9db9395c48d8e9dc271c111e5b6a84cbf6a3e3
529 716231 cb17bc0270468900ff529538abb575fa2926c7b8 3440 0f06413950818a9055a949b18a1cce5c2d085d29
530 747767 60a4384cdbf3ecba92d7b4320f7b52db72edebf0 3718 9483c9e623cb787170ca3f8c6d2f15608e03f33d
531 609393 c94cce0871f9a720ba9bd30675011d40f6c49060 3555 92a6b6e6b70ab41598cec48c56a9ba1fd45cd633
532 736439 cf4150f9eace5ee3a30f459305a040959cd59006 3762 00303d8237486c0e6ec1175b09a1f9eaf705963e
533 732571 f2394611dc7fe7fb8990ad29754622da3af41dd0 4452 1197752757cf226292a5c9da1f2247886c871108
534 603944 50d528b552a2e11294aa7e6b5e5b8ca331ee6c10 3784 3f3b0a4fe3e58ed6b86eb87b88c05ff068355b43
535 758317 ed3e24b8588d44876469f5fdffa531e86081e085 5442 e18b83b8565dbd7069ca4561b0424f93bc6e4a4e
536 747277 e7a66a83aeb316e5046b6b6716d6183969bc6ebe 4292 896abb4f140d1eb227e82c3a877a3a81829d54a9
537 651508 38c4920e6d708bc400a2c87ea4aca0d2799ecff4 3604 69a3f6f4e6e595bbd521d57f71624a30f875727c
538 685186 b73c3c60ea38d51375767b880db7791ac47f6d0b 1629 381f0e5df1b516a84d338d026bd6adaaf2167b16
539 676425 29d9eda1a1a20314608b352a1dc978d3b37f45ae 1625 27c78c05443fb4ad3ee35a64f816f648942b9a04
540 626747 e4fcf0733617dc06b777c64392ae49b1004c835e 1283 21c372febbf921ca49461a6b378b3e7aa3dc5b91
541 600893 988b61aba897369ec33467462754a92458d19b99 1146 66dac982889d0798267b53653cdf6e9c44dd5a3b
542 591044 f0beefb5f0b4c7da26475587a9cbe257dda3ce25 1424 dd56ebada6c5be9a79faa58f3d955aef537f5f8c
543 674210 4b73156f348714f605120f55060818c882bd2096 1139 29f0ca9277eaccb59509928c97aa4bd66f1a0526
544 715388 e87308e6cdb65251f8d244c18d9d888a2205a0e4 2141 52a16e90be198125fa5eabd1f69e0d5c7215740f
545 568519 d307907a1d67df4e950c89d3de50f255d28cf2c6 768 e692310f439e9caa1f4b962d55b9f07c002146d8
546 639499 9b328122f2a525df3eb4809b0fd025fab11daa05 1206 2d04bb84a52036a30a00f39ffba0ed9e3ce8e8ad
547 624413 73fdd4f8e7af3901cd4f5aabbb501cfdce58fc11 1536 e18a23c7b0267e7cbff74696730d1aafa483dd12
548 576318 f4cad4300865a97e993d32be735e97613eb426f0 1681 d7395493d7e912500cefc5fc13b0b66450bb1dde
549 686084 707585cea62b10e18dab0ca843c00854692468fa 1035 ab432ecace8dc4906ff420749699c74e8567f10a
550 743372 39770f8316c9fa1655e7cd508c0726c36e9064c3 1156 e2ffc3d28e9df47eccff75edc6ccabe168d66eb5
551 585430 5e1aa05c414fac88f2cbdf4ee9de1d4e7a56d387 1108 cf25d15dcea64bfb76b6a573df321a5cfe684e44
552 773680 945f2309172b88580601fb7b70fb355ea60abe55 1732 232f4c10f223f522d4d7ba6491906173e64e0f12
553 596960 ac6b466f4662f35cd25effe307177cedfc0b4d34 1646 be49f5636dedbb6c8e559b5f19bc00708ee4c6f9
554 634492 0886bee06fc6151df48b6a9caade76ce9631b562 1249 f1f601a95bcb7c8b78ae75e282980d35ee14f458
555 571155 a8a12302122004dc291602100c75e872e23766c4 1318 86cb89e13706fd0830f807d1a6bf8cf82549435d
556 688661 eb3411bd749c99d1ee67da8e36dc97414b839ac3 1813 d342af18a34126b6c67592d1dd01d4043f668bbd
557 571561 d750b2a977ef265727db3f691ccbe90bd212ed74 1948 3bb8acac2cc522214b4c9114737e2b03a56e53c3
558 645262 81d794786fffa928a8c0c9868388e15c03adde75 901 b4f6d350d5a29d3eda89a85d57864f83e3fcf27b
559 692015 76d174eaa8ab975eeacd12ef64409d58a94890f6 1554 21bd6def9d1274229232b2a5a0e2e9c051ff47ee
560 622194 59f9ed93e20b468b9c8b26cabfa38132cc3fcd0b 1623 b15bdb8a2526acef8abb7e35f9038aa6002fd89c
561 565728 c35351501f55a0ebd9885ee95f0aa7169bbfd62b 898 3392beefd74faf68b7ac94e1b759e1c4c1a05ee9
562 633348 7716cbafdc764f09b581b29bcbdded011ab7661b 2176 048a8d1976a09f752b12d4b3650510cda791aebb
563 686453 6cb54ab776e43c1627b37915b3f6a9f3a8487422 2541 431f6ffc349645f7f292dd84c0912ff2d41bc8b8
564 626724 f3ec0209353b6a3a16cb270457f0808a5aa6267b 3156 7314bb1f976f373c8a86c47f983a9ab29cb58635
565 773954 a0ada50e88476b7b262bb2c92aafcc0f576abfc3 4299 1c19f9ab81fdf2d4b92c679a9a926ceb5d4f1acd
566 670747 a8cd61ee4926ce75b0e2bf0a925410c6dabb2ec0 3021 188af73fbc8531ed6950791f03f7887ed7a12f39
567 775443 83dfc43ee43025e2f24606b07670d58dec6a3c4a 4446 b5bf15908af18ac6a648b8133bfe0b0ff8bf9b4c
568 660565 408e655cd402901559b1213fddf812b779f6c24b 4106 cad7d6fc678fb7b87cd39f743419ed031ad59e9a
569 792265 6cfb34f52fff4ee53039ddc44ad05db6dfe5379c 4838 66aea8b2e6da20c0eba44e1db2e56e9882ee9dd7
570 641302 04b9eae21ecb1089d350e2487ce8137093d9d95b 2324 314ced39ea8834e115e122b82968254628b61d6c
571 667559 002d80531ea58b799c06c965b93b446e4cebd6e5 3083 e67ee3e9d47b5baf112840788ce38f968de25cea
572 617428 2506347fa6bf9e8d90ccd4dedd285b843de72d5f 2403 734ec781cd542238a4353feae601111e9b9e5c40
573 662169 d9d50ec2eae3aa3328ebbedc2f66327c4fc483a0 2822 400ff298bc99ac96cc721570830091b953212390
574 666825 bda75fb54bbead850a84a3b2927e705319cbb650 3076 6a3e86e3adfd19144f924ff8cf9b12cbf670f06c
575 699892 c90f1daa1c258147e3249976af86c1885f5ddfae 2798 7b99365e2d5d66c97f5e4a2e953cb642e306aa79
576 780209 314954e2d44da0b1916f607e99c9e40c386eca64 4393 a31792a22d388c37c32ff097abf5edd9669cdb5a
577 740625 3afa3c46401eabecd1ee48b4d302248247adfe25 4366 43ef38358ad5cee39a699a91f492548ba6f4540e
578 711161 199747fbde01582c2e1b09613ff809fb6be177d0 4084 d89986fcf7825791dac2cc41f1b7c94f6d753634
579 746317 56be41af34081460530d503200dad5d3098559aa 3472 f7ffa2e271d0b05baa9922244f03fe7fee43be28
580 670983 a171d67d23506382d6d6ee60ef29274190540567 3841 cd030997b18cc97ae941505c0f5bc8502f78e519
581 750112 6ba69a2692877d14b536a631179cc55ef3e4839e 4816 8dcdc6a48ee4858ab7db4b698f0fd7a86a486fc9
582 658748 d12605ba008e4a47ae5410db74ee13e00be835ae 4696 989b4c0750fe096fa0c015d8768e4a5805922d32
583 713185 6a15caf1277c1b86370f23663ebcb65a25328904 3952 7f491ca437f6e2939626a5891451ce399bc07ce7
584 712089 ce3cb73cbe1bbc351f326873bb2eddfaa0e394ca 4495 584a2253ddd13d0307aa2abb131757ee4fccdccc
585 792412 616fc105c5c5fa02137ba03c987c59d67d6090ad 6039 0e1b8c06b43a4d51bfb6e55001e68bd75e9f83b1
586 688998 00618a0e2a0868d0134642a09b0f86b8207dd485 4559 763e5d29a57893f6aa02037d9adf7bd190aaf945
587 611593 744775512f8088dd0be037402b3906d5415fe63e 3609 f963be80f0aa56df682babd8fdccb96a23bafc31
588 746556 06d0b7c0a1dbfeb10137aa99bfb5690e0a66eeee 4540 08fef5f53bc999f64c7816f08cf7b9ac56542495
589 652201 803047e2cbfd17715312ff739485c72c0b7c31cf 4117 cc618e782e2136bd001aa8c0c45f6edc6f5818dc
590 677648 1bcf26802fbecd84c61b989595f714b9269eba26 3715 56d506831e0dd9d9693bfe0949e0108b96d80384
591 619507 c4f58a4810d453a37b326bd8506d41225d481f6f 3922 4b695f2b75ddf39aedefa9d86d78c41fd048af10
592 668099 7bc2888b66065dc699ff5ee15d0cb22b8b7bbb01 4766 182ec6342a01f52beddf34253f5653f7fd8409a6
593 637199 79dd9e40807b592d91d488de5a6539955e29b3c3 4068 a5e91244feb1eb7910011c0bff562c50d496b6bd
594 633750 573b25050f3a1e7f2a78de34eaacdacd44c7c59e 3940 57fa717a448a2e5592b8a71955c5e9b905c86f6a
595 604027 d824f14d3b5053cc17fdaf5032c1e97c6445b15f 3838 3f156cf46a75c815170bb9ddf6da27c233023eb5
596 581429 7e85eac6e80d57464f90ee74d3bd6ed100c629fc 3657 d975afc0ac6327b21cd637e6be92e9db0a23a74e
597 607964 99c24eef39e24b4f2cdfb9a5a4f138de54dd58df 3701 bfbb6fd3ef59f2ccd29ef8993747f96d6170f3ee
598 590453 922e7b2c5260b2eb94b565d646ab31119e6cd950 2636 a88166d10becec034949652243a0dfcd0888ac88
599 565545 0c6f57007ae0a1fe651a03aacbecad2974005a22 2571 855d0d4c0d86d98b27ce93a30bb6e188b17ffe9f
600 590814 2ca0ba07fc46583c4a032c94e24e9503ffdd6fa8 3754 e234e93dd212b869ae7efa54ce77c61bb8ac2154
601 473865 8df7adc3a4aed20eaa61e5f10fe168305e6a1aaf 2529 9ecbb9b9694913d4afd35b6ef5cc5934a64958ce
602 411143 1d172c0005dfdcc9aa9299ff548ff956ec006bfb 2091 cb1a546458202789c215814fa76a0583ab3db80b
603 409406 a33e7741a5d1c8d6f2f33bba285b9d2cc1767d2a 2044 9ef3a7af963838b54e31343c3a11f1b7b8815bce
604 367714 72cb7ef164bd5eafcfa970f8220441f1d9b3110e 2255 c442e616904b6d4a5d84840571a8f8db06051cfb
''';
