import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../quran/presentation/quran_reader.dart';
import '../../quran/presentation/quran_tafsir.dart';
import '../../quran/data/quran_content.dart' show TafsirText;
import '../data/religious_catalog.dart';
import '../data/religious_controller.dart';
import 'religious_widgets.dart';
export 'religious_widgets.dart' show ReligiousNavigationBar;

part 'religious_pages.dart';
part 'religious_details.dart';

class ReligiousHost extends StatefulWidget {
  const ReligiousHost({
    super.key,
    required this.controller,
    required this.onClose,
    this.active = true,
    this.initialCategoryAsRoot = false,
    this.initialCategory,
  });
  final ReligiousController controller;
  final VoidCallback onClose;
  final bool active;
  final bool initialCategoryAsRoot;
  final String? initialCategory;
  @override
  State<ReligiousHost> createState() => ReligiousHostState();
}

class ReligiousHostState extends State<ReligiousHost> {
  final navigator = GlobalKey<NavigatorState>();
  ReligiousController get controller => widget.controller;
  ReligiousCatalog get catalog => controller.catalog!;
  bool _requestedRefresh = false;
  void openCategory(String id) {
    if (id == 'feelings') {
      _push(_ReligiousTopicsPage(host: this), '/religious/feelings');
      return;
    }
    if (id == 'personal-adhkar') {
      openSaved(adhkar: true);
      return;
    }
    final category = catalog.byCategory[id];
    if (category == null) return;
    _push(
      _ReligiousCategoryPage(host: this, category: category),
      '/religious/$id',
    );
  }

  void openItem(ReligiousItem item) => _push(
    item.type == 'playlist'
        ? _ReligiousListeningPage(host: this, item: item)
        : _ReligiousDetailsPage(host: this, item: item),
    '/religious/content/${item.id}',
  );
  void openSaved({bool adhkar = false}) => _push(
    _ReligiousCategoryPage(host: this, saved: !adhkar, adhkar: adhkar),
    adhkar ? '/religious/adhkar' : '/religious/favorites',
  );
  void _push(Widget page, String name) => navigator.currentState?.push(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => page,
    ),
  );
  void back() {
    if (navigator.currentState?.canPop() == true) {
      navigator.currentState!.pop();
    } else {
      widget.onClose();
    }
  }

  void message(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> copy(BuildContext context, ReligiousItem item) async {
    await Clipboard.setData(ClipboardData(text: item.shareText));
    if (context.mounted) message(context, 'تم نسخ النص مع المصدر');
  }

  void share(BuildContext context, ReligiousItem item) {
    final box = context.findRenderObject() as RenderBox?;
    SharePlus.instance.share(
      ShareParams(
        text: item.shareText,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  void openQuran(ReligiousItem item, {bool tafsir = false}) {
    if (item.verseKeys.isEmpty) return;
    final verse = controller.quran.repository!.byKey[item.verseKeys.first]!;
    _push(
      tafsir
          ? QuranExplanation(
              controller: controller.quran,
              verse: verse,
              onPlay: controller.quran.audio.playVerse,
            )
          : QuranReader(
              controller: controller.quran,
              verse: verse,
              onFullscreenChanged: (_) {},
            ),
      '/religious/quran/${verse.key}',
    );
  }

  Future<void> play(BuildContext context, ReligiousItem item) async {
    if (controller.activeItem == item.id && controller.media.current != null) {
      await controller.media.toggle();
    } else {
      await controller.play(item);
    }
    if (context.mounted && controller.error != null) {
      message(context, controller.error!);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.loading) {
        return const Center(child: CircularProgressIndicator(color: rTeal));
      }
      if (controller.catalog == null) {
        return ReligiousEmpty(
          text: controller.error ?? 'المحتوى غير متاح',
          action: 'إعادة المحاولة',
          onAction: controller.load,
        );
      }
      if (!_requestedRefresh) {
        _requestedRefresh = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(controller.refresh(silent: true));
        });
      }
      return ColoredBox(
        color: ReligiousColors(context).background,
        child: PopScope<Object?>(
          canPop: !widget.active,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && widget.active) back();
          },
          child: Navigator(
            key: navigator,
            onGenerateInitialRoutes: (_, _) => [
              if (!widget.initialCategoryAsRoot ||
                  (catalog.byCategory[widget.initialCategory] == null &&
                      widget.initialCategory != 'feelings' &&
                      widget.initialCategory != 'personal-adhkar'))
                MaterialPageRoute<void>(
                  builder: (_) => _ReligiousHomePage(host: this),
                ),
              if (widget.initialCategory != null &&
                  catalog.byCategory[widget.initialCategory] != null)
                MaterialPageRoute<void>(
                  builder: (_) => _ReligiousCategoryPage(
                    host: this,
                    category: catalog.byCategory[widget.initialCategory],
                  ),
                ),
              if (widget.initialCategory == 'feelings')
                MaterialPageRoute<void>(
                  builder: (_) => _ReligiousTopicsPage(host: this),
                ),
              if (widget.initialCategory == 'personal-adhkar')
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _ReligiousCategoryPage(host: this, adhkar: true),
                ),
            ],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => _ReligiousHomePage(host: this),
            ),
          ),
        ),
      );
    },
  );
}

IconData _categoryIcon(String id) => switch (id) {
  'prophetic-duas' => Icons.mosque_outlined,
  'quran-duas' => Icons.menu_book_outlined,
  'friday' => Icons.account_balance_outlined,
  'names' => Icons.auto_awesome_outlined,
  'ruqya' => Icons.shield_outlined,
  'nawawi' => Icons.auto_stories_outlined,
  _ => Icons.groups_outlined,
};

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.host,
    required this.category,
    this.compact = false,
  });
  final ReligiousHostState host;
  final ReligiousCategory category;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final colors = ReligiousColors(context);
    return ReligiousCard(
      padding: EdgeInsets.zero,
      onTap: () {
        if (category.id == 'feelings-shortcut') {
          host._push(_ReligiousTopicsPage(host: host), '/religious/feelings');
        } else if (category.id == 'daily-shortcut') {
          host._push(
            _ReligiousCategoryPage(
              host: host,
              category: host.catalog.byCategory['sunnah-daily-life'],
              titleOverride: 'أدعية الحياة اليومية',
            ),
            '/religious/daily-duas',
          );
        } else {
          host.openCategory(category.id);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              right: compact ? null : 0,
              left: compact ? 0 : null,
              width: compact ? 92 : 72,
              child: Image.asset(rAsset(category.image), fit: BoxFit.cover),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: compact
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    end: compact ? Alignment.centerRight : Alignment.centerLeft,
                    colors: [
                      colors.card.withValues(alpha: 0),
                      colors.card,
                      colors.card,
                    ],
                    stops: const [0, .48, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                5,
                compact ? 9 : 6,
                compact ? 10 : 52,
                compact ? 9 : 6,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (!compact)
                          Icon(
                            _categoryIcon(category.id),
                            size: 17,
                            color: rGold,
                          ),
                        if (!compact) const SizedBox(height: 3),
                        Text(
                          category.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: rText(
                            context,
                            compact ? 13 : 11,
                            weight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Flexible(
                          child: Text(
                            compact
                                ? '${host.catalog.search(category: category.id).length} مادة'
                                : category.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: rText(
                              context,
                              compact ? 10 : 10,
                              color: colors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_left,
                    textDirection: TextDirection.ltr,
                    size: 21,
                    color: colors.heading,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.host,
    required this.item,
    required this.index,
    this.verse = false,
  });
  final ReligiousHostState host;
  final ReligiousItem item;
  final int index;
  final bool verse;
  @override
  Widget build(BuildContext context) {
    final colors = ReligiousColors(context);
    return ReligiousCard(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      onTap: () => host.openItem(item),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  tooltip: host.controller.favorites.contains(item.id)
                      ? 'إزالة من المفضلة'
                      : 'إضافة إلى المفضلة',
                  onPressed: () => host.controller.toggleFavorite(item.id),
                  icon: Icon(
                    host.controller.favorites.contains(item.id)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    color: rGold,
                    size: 20,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.subtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${item.number > 0 ? item.number : index + 1}',
                    style: rText(context, 9, color: rGold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  verse ? item.text.replaceAll('\n', ' ') : item.title,
                  maxLines: verse ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: verse
                      ? TextStyle(
                          fontFamily: 'AmiriQuran',
                          fontSize: 22,
                          color: colors.heading,
                          height: 1.6,
                        )
                      : rText(context, 12, weight: FontWeight.w800),
                ),
                Text(
                  verse
                      ? item.source
                      : item.summary.isNotEmpty
                      ? item.summary
                      : item.text.replaceAll('\n', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: rText(context, 10, color: colors.text),
                ),
                if (!verse && ['dua', 'hadith', 'quran'].contains(item.type))
                  Text(
                    item.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: rText(context, 8, color: colors.muted),
                  ),
              ],
            ),
          ),
          if (!verse) ...[
            const SizedBox(width: 6),
            SizedBox(
              width: 94,
              height: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0, .6, 1],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: Image.asset(rAsset(item.image), fit: BoxFit.cover),
                ),
              ),
            ),
          ],
          ReligiousRoundButton(
            icon: verse ? Icons.play_arrow : Icons.chevron_left,
            label: verse ? 'استماع ${item.title}' : 'تفاصيل ${item.title}',
            size: verse ? 29 : 24,
            filled: verse,
            onTap: () => verse ? host.play(context, item) : host.openItem(item),
          ),
        ],
      ),
    );
  }
}

class _ReligiousPlayer extends StatelessWidget {
  const _ReligiousPlayer({required this.host, this.compact = false});
  final ReligiousHostState host;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final media = host.controller.media;
    return ListenableBuilder(
      listenable: media,
      builder: (context, _) {
        if (media.current == null && !media.loading && media.error == null) {
          return const SizedBox.shrink();
        }
        final duration = media.duration ?? Duration.zero;
        final maximum = duration.inMilliseconds.toDouble();
        return ReligiousCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          media.current?.title ?? 'جارٍ تحميل الصوت',
                          style: rText(context, 12, weight: FontWeight.w800),
                        ),
                        Text(
                          media.current?.reciter ?? '',
                          style: rText(
                            context,
                            10,
                            color: ReligiousColors(context).muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ReligiousRoundButton(
                    icon: media.playing ? Icons.pause : Icons.play_arrow,
                    label: media.playing ? 'إيقاف مؤقت' : 'تشغيل',
                    filled: true,
                    onTap: media.toggle,
                  ),
                ],
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 4,
                    ),
                  ),
                  child: Slider(
                    value: media.position.inMilliseconds.toDouble().clamp(
                      0,
                      maximum > 0 ? maximum : 1,
                    ),
                    max: maximum > 0 ? maximum : 1,
                    onChanged: maximum > 0
                        ? (v) => media.seek(Duration(milliseconds: v.round()))
                        : null,
                    activeColor: rTeal,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_duration(media.position), style: rText(context, 10)),
                  Text(
                    maximum > 0 ? _duration(duration) : '—',
                    style: rText(context, 10),
                  ),
                ],
              ),
              if (!compact)
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  children: [
                    TextButton(
                      onPressed: () => media.setSpeed(
                        media.speed >= 2 ? 0.5 : media.speed + 0.25,
                      ),
                      child: Text('${media.speed}×'),
                    ),
                    ReligiousRoundButton(
                      icon: Icons.skip_next,
                      label: 'التالي',
                      onTap: () => media.skip(1),
                    ),
                    ReligiousRoundButton(
                      icon: Icons.skip_previous,
                      label: 'السابق',
                      onTap: () => media.skip(-1),
                    ),
                    ReligiousRoundButton(
                      icon: Icons.bedtime_outlined,
                      label: 'مؤقت النوم',
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        builder: (context) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final minutes in [0, 10, 20, 30, 60])
                                ListTile(
                                  title: Text(
                                    minutes == 0
                                        ? 'إلغاء المؤقت'
                                        : 'بعد $minutes دقيقة',
                                  ),
                                  onTap: () {
                                    media.setTimer(
                                      minutes == 0
                                          ? null
                                          : Duration(minutes: minutes),
                                    );
                                    Navigator.pop(context);
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              if (media.error != null)
                Text(
                  media.error!,
                  style: rText(
                    context,
                    11,
                    color: ReligiousColors(context).text,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _duration(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
