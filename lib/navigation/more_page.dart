import 'package:flutter/material.dart';

import '../app_appearance.dart';
import '../core/localization/app_localization.dart';
import 'feature_routes.dart';
import 'more_service_grid.dart';
import 'more_service_list.dart';

String _groupTitle(BuildContext context, String title) {
  final key = switch (title) {
    'العبادات والأذكار' => 'directory.group.worship',
    'رحلتك الإيمانية' => 'directory.group.journey',
    'القرآن والأدعية والسنن' => 'directory.group.quran',
    'مجتمع حق' => 'directory.group.community',
    'خدمات حق' => 'directory.group.services',
    _ => null,
  };
  return key == null ? title : context.tr(key, fallback: title);
}

class MorePage extends StatefulWidget {
  const MorePage({super.key, required this.onFeature});
  final ValueChanged<AppFeature> onFeature;

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';

  String _normalized(String value) => value
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .toLowerCase()
      .trim();

  bool _matches(AppFeature feature) => _normalized(
    '${feature.localizedTitle(context)} ${feature.title} ${feature.subtitle ?? ''}',
  ).contains(_query);

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final appearance = AppearanceScope.of(context);
    final layout = appearance.moreDirectoryLayout;
    final results = AppFeature.values.where(_matches).toList();
    final groups = _query.isEmpty
        ? moreServiceGroups
        : <(String, List<AppFeature>)>[
            (context.tr('directory.results', fallback: 'نتائج البحث'), results),
          ];
    return ColoredBox(
      color: palette.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('directory.more', fallback: 'المزيد'),
                      style: TextStyle(
                        color: palette.heading,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Material(
                    color: palette.paleTeal,
                    shape: const CircleBorder(),
                    child: PopupMenuButton<MoreDirectoryLayout>(
                      key: const ValueKey('more-layout'),
                      tooltip: context.tr(
                        'directory.layout',
                        fallback: 'طريقة العرض',
                      ),
                      icon: Icon(
                        layout == MoreDirectoryLayout.grid
                            ? Icons.grid_view_outlined
                            : Icons.view_agenda_outlined,
                        color: palette.tealHeading,
                      ),
                      color: palette.surface,
                      elevation: 0,
                      position: PopupMenuPosition.under,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: palette.border),
                      ),
                      onSelected: (value) {
                        if (value == layout) return;
                        if (_scroll.hasClients) _scroll.jumpTo(0);
                        appearance.setMoreDirectoryLayout(value);
                      },
                      itemBuilder: (context) => [
                        for (final (value, label, icon) in [
                          (
                            MoreDirectoryLayout.grid,
                            context.tr('directory.grid', fallback: 'شبكة'),
                            Icons.grid_view_outlined,
                          ),
                          (
                            MoreDirectoryLayout.list,
                            context.tr(
                              'directory.list',
                              fallback: 'قائمة مصوّرة',
                            ),
                            Icons.view_agenda_outlined,
                          ),
                        ])
                          PopupMenuItem(
                            value: value,
                            child: Directionality(
                              textDirection: Directionality.of(context),
                              child: Row(
                                children: [
                                  Icon(
                                    icon,
                                    color: palette.tealHeading,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: TextStyle(color: palette.heading),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  if (value == layout)
                                    Icon(
                                      Icons.check,
                                      color: palette.tealHeading,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: palette.paleTeal,
                    shape: const CircleBorder(),
                    child: IconButton(
                      key: const ValueKey('more-settings'),
                      tooltip: context.tr(
                        'directory.settings',
                        fallback: 'الإعدادات',
                      ),
                      onPressed: () => widget.onFeature(AppFeature.settings),
                      icon: Icon(
                        Icons.settings_outlined,
                        color: palette.tealHeading,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tileHeight = layout == MoreDirectoryLayout.grid
                      ? moreServiceTileHeight(context, constraints.maxWidth)
                      : 0.0;
                  return CustomScrollView(
                    key: const PageStorageKey('more-directory'),
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                        sliver: SliverToBoxAdapter(
                          child: TextField(
                            key: const ValueKey('more-search'),
                            controller: _search,
                            onChanged: (value) =>
                                setState(() => _query = _normalized(value)),
                            decoration: InputDecoration(
                              hintText: context.tr(
                                'directory.search',
                                fallback: 'ابحث عن خدمة…',
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: palette.muted,
                              ),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: context.tr(
                                        'directory.clear',
                                        fallback: 'مسح البحث',
                                      ),
                                      onPressed: () {
                                        _search.clear();
                                        setState(() => _query = '');
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                              filled: true,
                              fillColor: palette.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: palette.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: palette.border),
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (final (title, features) in groups) ...[
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                          sliver: SliverToBoxAdapter(
                            child: Semantics(
                              header: true,
                              child: Text(
                                _groupTitle(context, title),
                                style: TextStyle(
                                  color: palette.heading,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (layout == MoreDirectoryLayout.grid)
                          MoreServiceGrid(
                            features: features,
                            tileHeight: tileHeight,
                            onFeature: widget.onFeature,
                          )
                        else
                          MoreServiceList(
                            features: features,
                            onFeature: widget.onFeature,
                          ),
                      ],
                      if (_query.isNotEmpty && results.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              context.tr(
                                'directory.empty',
                                fallback: 'لا توجد خدمات تطابق بحثك',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: palette.muted),
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 110)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DirectoryHeader extends StatelessWidget {
  const DirectoryHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.maxTitleLines,
    this.onBack,
    this.imageAsset = 'assets/navigation/more_header.png',
  });
  final String title, subtitle;
  final String imageAsset;
  final int? maxTitleLines;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      height:
          218 +
          (onBack == null
              ? 0
              : 60 +
                    (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(
                          0,
                          3,
                        ) *
                        180) +
          MediaQuery.paddingOf(context).top +
          (imageAsset == 'assets/navigation/more_header.png'
              ? 0
              : (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 3) *
                    110),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(imageAsset, fit: BoxFit.cover),
          if (palette.dark)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    palette.background,
                    palette.background.withValues(alpha: .85),
                    Colors.transparent,
                  ],
                  stops: const [0, .4, 1],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              MediaQuery.paddingOf(context).top + 25,
              20,
              24,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * .53,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: maxTitleLines,
                      overflow: maxTitleLines == null
                          ? null
                          : TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.heading,
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: palette.dark
                            ? palette.muted
                            : const Color(0xFF285571),
                        fontSize: 13,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onBack != null)
            Positioned(
              left: 16,
              top: MediaQuery.paddingOf(context).top + 18,
              child: Material(
                color: palette.surface,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: onBack,
                  tooltip: context.tr('directory.back', fallback: 'رجوع'),
                  icon: Icon(Icons.arrow_back_ios_new, color: palette.heading),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
