import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../app_appearance.dart';
import '../quran/data/quran_repository.dart';

enum ShareCardFormat { square, story }

enum ShareCardTheme { ivory, navy, teal }

class ShareCardContent {
  const ShareCardContent({
    required this.text,
    required this.source,
    required this.attribution,
    this.verseKeys = const [],
  });
  factory ShareCardContent.quran(
    QuranRepository repository,
    List<String> keys,
  ) {
    if (keys.isEmpty ||
        keys.toSet().length != keys.length ||
        !keys.every(repository.byKey.containsKey)) {
      throw ArgumentError('A valid verse selection is required');
    }
    final verses = keys.map((key) => repository.byKey[key]!).toList();
    final first = verses.first;
    if (verses.any((verse) => verse.surah != first.surah) ||
        List.generate(verses.length, (i) => first.ayah + i).join(',') !=
            verses.map((verse) => verse.ayah).join(',')) {
      throw ArgumentError('Select consecutive verses in one surah');
    }
    return ShareCardContent(
      text: verses.map((verse) => verse.text).join('\n'),
      source:
          'سورة ${repository.surah(first.surah).name} • ${verses.length == 1 ? 'الآية ${first.ayah}' : 'الآيات ${first.ayah}–${verses.last.ayah}'}',
      attribution: 'القرآن الكريم • Tanzil.net • ${repository.sourceUrl}',
      verseKeys: List.unmodifiable(keys),
    );
  }
  final String text, source, attribution;
  final List<String> verseKeys;
}

class ShareCardStyle {
  const ShareCardStyle({
    this.format = ShareCardFormat.square,
    this.theme = ShareCardTheme.ivory,
    this.font = 'AmiriQuran',
    this.fontSize = 64,
  });
  final ShareCardFormat format;
  final ShareCardTheme theme;
  final String font;
  final double fontSize;
  ShareCardStyle copyWith({
    ShareCardFormat? format,
    ShareCardTheme? theme,
    String? font,
    double? fontSize,
  }) => ShareCardStyle(
    format: format ?? this.format,
    theme: theme ?? this.theme,
    font: font ?? this.font,
    fontSize: fontSize ?? this.fontSize,
  );
}

class ShareCardImage {
  const ShareCardImage(
    this.bytes,
    this.content,
    this.size,
    this.actualFontSize,
  );
  final Uint8List bytes;
  final ShareCardContent content;
  final Size size;
  final double actualFontSize;
}

class ShareCardRenderer {
  static Future<ShareCardImage> render(
    ShareCardContent content,
    ShareCardStyle style,
  ) async {
    if (content.text.trim().isEmpty ||
        content.source.trim().isEmpty ||
        content.text.length > 100000 ||
        !['AmiriQuran', 'QuranUI', 'Tajawal'].contains(style.font) ||
        style.fontSize < 24 ||
        style.fontSize > 100) {
      throw ArgumentError('Invalid share card');
    }
    final size = Size(
      1080,
      style.format == ShareCardFormat.square ? 1080 : 1920,
    );
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    final background = switch (style.theme) {
      ShareCardTheme.ivory => const Color(0xFFFFFCF7),
      ShareCardTheme.navy => const Color(0xFF102A43),
      ShareCardTheme.teal => const Color(0xFF075C57),
    };
    final ink = style.theme == ShareCardTheme.ivory
        ? const Color(0xFF102A43)
        : const Color(0xFFFFFCF7);
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final border = Paint()
      ..color = const Color(0xFFC7A45A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(36, 36, size.width - 72, size.height - 72),
        const Radius.circular(34),
      ),
      border,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(48, 48, size.width - 96, size.height - 96),
        const Radius.circular(26),
      ),
      border..strokeWidth = .7,
    );
    TextPainter painter(String text, TextStyle textStyle) => TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    );
    final heading = painter(
      'حق • دعاء وذكر',
      const TextStyle(
        fontFamily: 'QuranUI',
        fontSize: 26,
        color: Color(0xFFC7A45A),
      ),
    )..layout(maxWidth: 900);
    heading.paint(canvas, Offset((1080 - heading.width) / 2, 85));
    final footer = painter(
      content.source,
      TextStyle(fontFamily: 'QuranUI', fontSize: 28, color: ink),
    )..layout(maxWidth: 880);
    final attribution = painter(
      content.attribution,
      TextStyle(
        fontFamily: 'QuranUI',
        fontSize: 16,
        color: ink.withValues(alpha: .78),
      ),
    )..layout(maxWidth: 870);
    final top = 190.0,
        bottom = size.height - 155 - footer.height - attribution.height;
    var fontSize = style.fontSize;
    TextPainter? text;
    while (fontSize >= 18) {
      text = painter(
        content.text,
        TextStyle(
          fontFamily: style.font,
          fontSize: fontSize,
          color: ink,
          height: 1.9,
        ),
      )..layout(maxWidth: 880);
      if (text.height <= bottom - top) break;
      text.dispose();
      text = null;
      fontSize -= 1;
    }
    if (text == null) {
      heading.dispose();
      footer.dispose();
      attribution.dispose();
      recorder.endRecording().dispose();
      throw StateError('النص طويل لهذه البطاقة؛ اختر آيات أقل أو مقاس القصة');
    }
    text.paint(
      canvas,
      Offset(
        (size.width - text.width) / 2,
        top + (bottom - top - text.height) / 2,
      ),
    );
    final ornamentY = size.height - 150 - footer.height - attribution.height;
    canvas.drawLine(
      Offset(350, ornamentY),
      Offset(730, ornamentY),
      border..strokeWidth = 1,
    );
    final diamond = Path()
      ..moveTo(540, ornamentY - 8)
      ..lineTo(548, ornamentY)
      ..lineTo(540, ornamentY + 8)
      ..lineTo(532, ornamentY)
      ..close();
    canvas.drawPath(diamond, Paint()..color = const Color(0xFFC7A45A));
    footer.paint(
      canvas,
      Offset(
        (size.width - footer.width) / 2,
        size.height - 125 - footer.height - attribution.height,
      ),
    );
    attribution.paint(
      canvas,
      Offset(
        (size.width - attribution.width) / 2,
        size.height - 100 - attribution.height,
      ),
    );
    final picture = recorder.endRecording(),
        image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    heading.dispose();
    footer.dispose();
    attribution.dispose();
    text.dispose();
    return ShareCardImage(bytes!.buffer.asUint8List(), content, size, fontSize);
  }
}

class ShareCardExporter {
  static const channel = MethodChannel(
    'com.haqfoundation.haq_app/image_export',
  );
  static Future<bool> save(Uint8List bytes) async =>
      await channel.invokeMethod<bool>('saveImage', {
        'bytes': bytes,
        'name': 'haq-${DateTime.now().millisecondsSinceEpoch}.png',
      }) ??
      false;
}

Future<void> chooseContentShare(
  BuildContext context,
  ShareCardContent content, {
  QuranRepository? repository,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: false,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('مشاركة النص'),
            onTap: () => Navigator.pop(context, 'text'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('مشاركة كصورة'),
            onTap: () => Navigator.pop(context, 'image'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'image') {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ShareCardEditor(content: content, repository: repository),
      ),
    );
  } else if (choice == 'text') {
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: '${content.text}\n\n${content.source}\n${content.attribution}',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّرت المشاركة؛ يمكنك نسخ النص')),
        );
      }
    }
  }
}

class ShareCardEditor extends StatefulWidget {
  const ShareCardEditor({
    super.key,
    required this.content,
    this.repository,
    this.renderer,
  });
  final ShareCardContent content;
  final QuranRepository? repository;
  final Future<ShareCardImage> Function(ShareCardContent, ShareCardStyle)?
  renderer;
  @override
  State<ShareCardEditor> createState() => _ShareCardEditorState();
}

class _ShareCardEditorState extends State<ShareCardEditor> {
  late ShareCardContent content = widget.content;
  ShareCardStyle style = const ShareCardStyle();
  ShareCardImage? _image;
  String? _error;
  bool _working = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    if (content.verseKeys.length > 20 && widget.repository != null) {
      content = ShareCardContent.quran(widget.repository!, [
        content.verseKeys.first,
      ]);
    }
    unawaitedRender();
  }

  void unawaitedRender() {
    unawaited(_render());
  }

  Future<void> _render() async {
    final revision = ++_revision;
    setState(() {
      _image = null;
      _error = null;
    });
    try {
      final result = await (widget.renderer ?? ShareCardRenderer.render)(
        content,
        style,
      );
      if (mounted && revision == _revision) setState(() => _image = result);
    } catch (e) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = e is StateError
              ? e.message
              : 'تعذّرت معاينة الصورة؛ أعد المحاولة',
        );
      }
    }
  }

  void _change(ShareCardStyle next) {
    style = next;
    unawaitedRender();
  }

  Future<void> _export(bool save) async {
    final image = _image;
    if (image == null || _working) return;
    setState(() => _working = true);
    try {
      if (save) {
        final saved = await ShareCardExporter.save(image.bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(saved ? 'تم حفظ الصورة' : 'أُلغي حفظ الصورة'),
            ),
          );
        }
      } else {
        final directory = await getTemporaryDirectory();
        final file = File(
          '${directory.path}/haq-card-${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(image.bytes, flush: true);
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'image/png')],
            text: image.content.source,
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size,
          ),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'الحفظ المباشر متاح على Android وiOS؛ يمكنك مشاركة الصورة',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذّر حفظ أو مشاركة الصورة؛ تحقق من الإذن وأعد المحاولة',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context), repository = widget.repository;
    final first = content.verseKeys.isEmpty
        ? null
        : repository?.byKey[content.verseKeys.first];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(title: const Text('صورة الآية والمحتوى')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<ShareCardFormat>(
              segments: const [
                ButtonSegment(
                  value: ShareCardFormat.square,
                  label: Text('مربع'),
                ),
                ButtonSegment(value: ShareCardFormat.story, label: Text('قصة')),
              ],
              selected: {style.format},
              onSelectionChanged: _working
                  ? null
                  : (value) => _change(style.copyWith(format: value.single)),
            ),
            const SizedBox(height: 12),
            if (first != null)
              if (widget.content.verseKeys.length > 20)
                const Text(
                  'اختر نطاق الآيات للصورة؛ مشاركة النص تحتفظ بالنص الكامل.',
                ),
            if (first != null)
              Row(
                children: [
                  Text('من الآية ${first.ayah} إلى '),
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: repository!.byKey[content.verseKeys.last]!.ayah,
                      items: [
                        for (
                          var i = first.ayah;
                          i <=
                              math.min(
                                first.ayah + 19,
                                repository.surah(first.surah).ayahCount,
                              );
                          i++
                        )
                          DropdownMenuItem(value: i, child: Text('$i')),
                      ],
                      onChanged: _working
                          ? null
                          : (end) {
                              if (end != null) {
                                content = ShareCardContent.quran(repository, [
                                  for (var i = first.ayah; i <= end; i++)
                                    '${first.surah}:$i',
                                ]);
                                unawaitedRender();
                              }
                            },
                    ),
                  ),
                ],
              ),
            Wrap(
              spacing: 8,
              children: [
                for (final theme in ShareCardTheme.values)
                  ChoiceChip(
                    label: Text(['عاجي', 'كحلي', 'فيروزي'][theme.index]),
                    selected: style.theme == theme,
                    onSelected: _working
                        ? null
                        : (_) => _change(style.copyWith(theme: theme)),
                  ),
              ],
            ),
            Row(
              children: [
                const Text('الخط'),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: style.font,
                    items: const [
                      DropdownMenuItem(
                        value: 'AmiriQuran',
                        child: Text('أميري القرآن'),
                      ),
                      DropdownMenuItem(
                        value: 'QuranUI',
                        child: Text('القاهرة'),
                      ),
                      DropdownMenuItem(value: 'Tajawal', child: Text('تجوال')),
                    ],
                    onChanged: _working
                        ? null
                        : (value) {
                            if (value != null) {
                              _change(style.copyWith(font: value));
                            }
                          },
                  ),
                ),
              ],
            ),
            Text('حجم الخط: ${style.fontSize.round()}'),
            Slider(
              min: 24,
              max: 100,
              divisions: 38,
              value: style.fontSize,
              onChanged: _working
                  ? null
                  : (size) =>
                        setState(() => style = style.copyWith(fontSize: size)),
              onChangeEnd: _working ? null : (_) => unawaitedRender(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, style: TextStyle(color: p.heading)),
              )
            else if (_image == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Column(
                children: [
                  Semantics(
                    label: 'معاينة الصورة بالنص والمصدر',
                    image: true,
                    child: Image.memory(
                      _image!.bytes,
                      key: const ValueKey('share-card-preview'),
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (_image!.actualFontSize < style.fontSize)
                    Text(
                      'صُغّر الخط تلقائيًا إلى ${_image!.actualFontSize.round()} لإظهار النص كاملًا',
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                ],
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  key: const ValueKey('share-card-save'),
                  onPressed: _working || _image == null
                      ? null
                      : () => _export(true),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('حفظ الصورة'),
                ),
                OutlinedButton.icon(
                  onPressed: _working || _image == null
                      ? null
                      : () => _export(false),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('مشاركة الصورة'),
                ),
              ],
            ),
            if (_working) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'النص والمصدر محفوظان كما هما؛ لا يمكن تعديل نص الآية داخل المصمم.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ],
        ),
      ),
    );
  }
}
