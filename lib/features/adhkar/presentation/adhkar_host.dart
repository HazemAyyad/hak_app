import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../sharing/share_card.dart';

import '../../../app_appearance.dart';
import '../../../navigation/feature_routes.dart';
import '../../../navigation/more_page.dart';
import '../../quran/data/quran_audio_models.dart';
import '../../quran/data/quran_repository.dart';
import '../../quran/presentation/quran_audio_widgets.dart';
import '../../religious_activity/data/activity_controller.dart';
import '../../religious_activity/data/activity_models.dart';
import '../../religious_content/data/religious_controller.dart';
import '../data/adhkar_repository.dart';
import '../data/adhkar_session_controller.dart';
import '../data/adhkar_volume_controls.dart';
import '../data/personal_adhkar.dart';

part 'adhkar_reader.dart';
part 'personal_adhkar_page.dart';
part 'adhkar_empty_group.dart';

class AdhkarSectionPage extends StatefulWidget {
  const AdhkarSectionPage({
    super.key,
    required this.controller,
    required this.onFeature,
    required this.onExit,
    this.active = true,
    this.initialRepository,
  });
  final ReligiousController controller;
  final ValueChanged<AppFeature> onFeature;
  final VoidCallback onExit;
  final bool active;
  final AdhkarRepository? initialRepository;
  @override
  State<AdhkarSectionPage> createState() => AdhkarSectionPageState();
}

class AdhkarSectionPageState extends State<AdhkarSectionPage> {
  final navigator = GlobalKey<NavigatorState>();
  final routes = RouteObserver<ModalRoute<dynamic>>();
  final visible = ValueNotifier(true);
  Future<AdhkarRepository>? _source;
  bool _working = false;
  int _preparation = 0;
  final _sessions = <AdhkarSessionController>{};
  ReligiousActivityController? _activity;
  String? _activityScope;
  void _bindActivity(ReligiousActivityController value) {
    if (identical(_activity, value)) return;
    _activity?.removeListener(_accountChanged);
    _activity = value;
    _activityScope = value.scope;
    value.addListener(_accountChanged);
  }

  void _accountChanged() {
    if (!mounted || _activity?.scope == _activityScope) return;
    _activityScope = _activity?.scope;
    _preparation++;
    setState(() => _working = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) navigator.currentState?.popUntil((route) => route.isFirst);
    });
  }

  Future<AdhkarRepository> get source => _source ??=
      (widget.initialRepository ?? widget.controller.initialAdhkarCatalog) !=
          null
      ? Future.value(
          widget.initialRepository ?? widget.controller.initialAdhkarCatalog!,
        )
      : AdhkarRepository.load(widget.controller.quran.repository!);
  @override
  void initState() {
    super.initState();
    visible.value = widget.active;
  }

  @override
  void didUpdateWidget(covariant AdhkarSectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    visible.value = widget.active;
  }

  @override
  void dispose() {
    _activity?.removeListener(_accountChanged);
    for (final session in _sessions) {
      session.dispose();
    }
    _sessions.clear();
    visible.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _prepare(
    Future<void> Function(AdhkarRepository, ReligiousActivityController) action,
  ) async {
    if (_working) return;
    final preparation = ++_preparation;
    setState(() => _working = true);
    try {
      final repository = await source;
      final activity = await widget.controller.activity;
      if (!mounted) return;
      _bindActivity(activity);
      await action(repository, activity);
    } catch (_) {
      _message('تعذّر فتح الأذكار؛ بياناتك محفوظة، أعد المحاولة');
    } finally {
      if (mounted && _working && preparation == _preparation) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> openGroup(String id) => _prepare((repository, activity) async {
    final scope = activity.scope;
    final library = await repository.library(activity.store, scope);
    if (!mounted || activity.scope != scope) return;
    final group = library.groups.where((g) => g.id == id).firstOrNull;
    if (group == null) {
      _message('هذه المجموعة غير متاحة حاليًا');
      return;
    }
    if (group.itemIds.isEmpty) {
      setState(() => _working = false);
      await navigator.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => _EmptyDhikrGroup(
            host: this,
            repository: repository,
            activity: activity,
            group: group,
            library: library,
            owner: scope,
          ),
        ),
      );
      return;
    }
    final session = await AdhkarSessionController.open(
      activity: activity,
      group: group,
      library: library,
      catalogVersion: repository.version,
    );
    if (!mounted || activity.scope != scope) {
      session.dispose();
      return;
    }
    setState(() => _working = false);
    _sessions.add(session);
    await navigator.currentState?.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/adhkar/read/$id'),
        builder: (_) => _AdhkarReader(host: this, controller: session),
      ),
    );
    if (_sessions.remove(session)) {
      await session.flush();
      session.dispose();
    }
  });
  Future<void> openPersonal() => _prepare((repository, activity) async {
    setState(() => _working = false);
    await navigator.currentState?.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/adhkar/personal'),
        builder: (_) => _PersonalAdhkarPage(
          host: this,
          repository: repository,
          activity: activity,
        ),
      ),
    );
  });
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      NavigatorPopHandler<void>(
        enabled: widget.active,
        onPopWithResult: (_) => navigator.currentState?.maybePop(),
        child: Navigator(
          key: navigator,
          observers: [routes],
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => PopScope<Object?>(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && widget.active) widget.onExit();
              },
              child: _AdhkarIndex(host: this),
            ),
          ),
        ),
      ),
      if (_working)
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black26,
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
    ],
  );
}

class _AdhkarIndex extends StatefulWidget {
  const _AdhkarIndex({required this.host});
  final AdhkarSectionPageState host;
  @override
  State<_AdhkarIndex> createState() => _AdhkarIndexState();
}

class _AdhkarIndexState extends State<_AdhkarIndex> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final host = widget.host, colors = AppPalette.of(context);
    return ColoredBox(
      color: colors.background,
      child: ListenableBuilder(
        listenable: host.widget.controller.quran,
        builder: (context, _) => host.widget.controller.quran.repository == null
            ? const Center(child: CircularProgressIndicator())
            : FutureBuilder<AdhkarRepository>(
                future: host.source,
                builder: (context, snapshot) {
                  final repository = snapshot.data;
                  final needle = normalizeQuranSearch(query);
                  final groups =
                      repository?.groups
                          .where(
                            (g) =>
                                normalizeQuranSearch(g.title).contains(needle),
                          )
                          .toList() ??
                      [];
                  return CustomScrollView(
                    key: const PageStorageKey('adhkar-section'),
                    slivers: [
                      const SliverToBoxAdapter(
                        child: DirectoryHeader(
                          title: 'أذكار المسلم',
                          subtitle: 'اذكر الله واطمئن',
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
                        sliver: SliverList.list(
                          children: [
                            TextField(
                              key: const ValueKey('adhkar-search'),
                              onChanged: (value) =>
                                  setState(() => query = value),
                              decoration: _input(
                                context,
                                'ابحث في مجموعات الأذكار...',
                                icon: Icons.search,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                ActionChip(
                                  key: const ValueKey('adhkar-personal'),
                                  avatar: const Icon(Icons.edit_note),
                                  label: const Text('أذكاري الشخصية'),
                                  onPressed: host.openPersonal,
                                ),
                                ActionChip(
                                  avatar: const Icon(Icons.favorite_border),
                                  label: const Text('الأذكار المحفوظة'),
                                  onPressed: () => host.openGroup(
                                    'group:${AdhkarRepository.savedGroupId}',
                                  ),
                                ),
                                ActionChip(
                                  key: const ValueKey('adhkar-personalAdhkar'),
                                  avatar: const Icon(Icons.bookmarks_outlined),
                                  label: const Text('المواد المحفوظة سابقًا'),
                                  onPressed: () => host.widget.onFeature(
                                    AppFeature.personalAdhkar,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (snapshot.hasError)
                              _notice(
                                context,
                                'تعذّر تحميل المصدر',
                                action: () {
                                  host._source = null;
                                  setState(() {});
                                },
                              ),
                            if (snapshot.connectionState !=
                                ConnectionState.done)
                              const Center(child: CircularProgressIndicator()),
                            if (repository != null && groups.isEmpty)
                              _notice(context, 'لا توجد مجموعات تطابق بحثك'),
                            LayoutBuilder(
                              builder: (context, constraints) => GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: groups.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount:
                                          constraints.maxWidth >= 600 ? 3 : 2,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                      mainAxisExtent: MediaQuery.textScalerOf(
                                        context,
                                      ).scale(104).clamp(118, 170),
                                    ),
                                itemBuilder: (context, index) {
                                  final group = groups[index];
                                  return _card(
                                    context,
                                    onTap: () => host.openGroup(group.id),
                                    key: ValueKey(group.id),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Icon(
                                          _groupIcon(group.icon),
                                          color: colors.gold,
                                          size: 29,
                                        ),
                                        Text(
                                          group.title,
                                          style: TextStyle(
                                            color: colors.heading,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'حصن المسلم • نصوص وأعداد موثّقة، وتقدّمك محفوظ على الجهاز',
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 12,
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

IconData _groupIcon(String name) => switch (name) {
  'sun' => Icons.wb_sunny_outlined,
  'moon' => Icons.nightlight_outlined,
  'mosque' => Icons.mosque_outlined,
  'home' => Icons.home_outlined,
  'compass' => Icons.explore_outlined,
  _ => Icons.eco_outlined,
};
InputDecoration _input(BuildContext context, String hint, {IconData? icon}) {
  final colors = AppPalette.of(context);
  return InputDecoration(
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon, color: colors.tealHeading),
    filled: true,
    fillColor: colors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: colors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide(color: colors.border),
    ),
  );
}

Widget _card(
  BuildContext context, {
  required Widget child,
  VoidCallback? onTap,
  Key? key,
  EdgeInsets padding = const EdgeInsets.all(16),
}) {
  final colors = AppPalette.of(context);
  return Material(
    key: key,
    color: colors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: colors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

Widget _notice(BuildContext context, String text, {VoidCallback? action}) =>
    Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppPalette.of(context).muted, height: 1.8),
          ),
          if (action != null)
            TextButton(onPressed: action, child: const Text('إعادة المحاولة')),
        ],
      ),
    );

Future<bool> _confirm(
  BuildContext context,
  String title,
  String text, {
  String accept = 'تأكيد',
}) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(accept),
          ),
        ],
      ),
    ) ??
    false;
