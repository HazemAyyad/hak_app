import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../app_appearance.dart';
import '../../../navigation/more_page.dart';
import '../data/prayer_controller.dart';
import '../data/prayer_models.dart';
import '../data/heading_controller.dart';
import '../data/mosque_repository.dart';
import '../data/prayer_alert.dart';
import '../data/adhan_library.dart';
import '../data/place_catalog.dart';
import 'qibla_dial.dart';
import 'prayer_location_picker.dart';

part 'prayer_settings.dart';
part 'prayer_adhan_settings.dart';
part 'prayer_reminder_recordings.dart';
part 'adhan_screen_preview.dart';
part 'prayer_alert_page.dart';
part 'qibla_page.dart';

final prayerRoutes = RouteObserver<ModalRoute<dynamic>>();

Widget _panel(BuildContext context, Widget child) => Container(
  width: double.infinity,
  margin: const EdgeInsets.only(bottom: 12),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: AppPalette.of(context).surface,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: AppPalette.of(context).border),
  ),
  child: Material(type: MaterialType.transparency, child: child),
);
Widget _notice(BuildContext context, String text) => _panel(
  context,
  Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(color: AppPalette.of(context).muted, height: 1.7),
  ),
);

class PrayerPage extends StatelessWidget {
  const PrayerPage({
    super.key,
    required this.controller,
    this.beforeAudio,
    this.enableReminders,
  });
  final PrayerController controller;
  final Future<void> Function()? beforeAudio;
  final Future<bool> Function()? enableReminders;
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppPalette.of(context).background,
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: DirectoryHeader(
                title: 'مواقيت الصلاة',
                subtitle: 'مواقيتك حسب الموقع والطريقة المختارة',
                onBack: () => Navigator.maybePop(context),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  _panel(
                    context,
                    Column(
                      children: [
                        Text(
                          controller.config.location?.label ??
                              'لم تحدد موقعاً بعد',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppPalette.of(context).tealHeading,
                          ),
                        ),
                        Text(controller.hijriLabel),
                        const Text(
                          'تقويم أم القرى مع التصحيح المختار؛ قد يختلف إعلان بداية الشهر محلياً',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11),
                        ),
                        if (controller.upcoming case final next?) ...[
                          const SizedBox(height: 16),
                          Text('الصلاة القادمة: ${next.name.label}'),
                          Text(
                            controller.countdown,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 36,
                              color: AppPalette.of(context).tealHeading,
                            ),
                          ),
                        ],
                        if (controller.today case final today?)
                          for (final moment in today.moments)
                            _PrayerTimeRow(
                              controller: controller,
                              moment: moment,
                              beforeAudio: beforeAudio,
                              enableReminders: enableReminders,
                            ),
                      ],
                    ),
                  ),
                  if (controller.error case final error?)
                    _notice(context, error),
                  if (controller.calculationError case final error?)
                    _notice(context, error),
                  FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => PrayerAdhanSettingsPage(
                          controller: controller,
                          beforeAudio: beforeAudio,
                          enableReminders: enableReminders,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.tune),
                    label: const Text('إعدادات الأذان'),
                  ),
                  const SizedBox(height: 12),
                  _notice(
                    context,
                    'طريقة الحساب: ${controller.config.method.label}. المواقيت محسوبة وليست جدولاً رسمياً للمسجد. راجعها مع الجهة المحلية وعدّل الفروق عند الحاجة.',
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class MosquesPage extends StatefulWidget {
  const MosquesPage({super.key, required this.controller, this.repository});
  final PrayerController controller;
  final MosqueRepository? repository;
  @override
  State<MosquesPage> createState() => _MosquesPageState();
}

class _MosquesPageState extends State<MosquesPage> {
  late final MosqueRepository _repository =
      widget.repository ?? MosqueRepository();
  List<NearbyMosque>? _items;
  String? _error;
  bool _busy = false;
  int _revision = 0;
  PrayerLocation? _place;
  String? _scope;
  @override
  void initState() {
    super.initState();
    _place = widget.controller.config.location;
    _scope = widget.controller.scope;
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (_place != widget.controller.config.location ||
        _scope != widget.controller.scope) {
      _revision++;
      _repository.cancel();
      _place = widget.controller.config.location;
      _scope = widget.controller.scope;
      if (mounted) {
        setState(() {
          _items = null;
          _error = null;
          _busy = false;
        });
      }
    }
  }

  Future<void> _search() async {
    final place = widget.controller.config.location;
    if (place == null || _busy) return;
    final token = ++_revision;
    final owner = widget.controller.scope;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final items = await _repository.search(place);
      if (mounted && token == _revision && owner == widget.controller.scope) {
        setState(() => _items = items);
      }
    } catch (e) {
      if (mounted && token == _revision) {
        setState(
          () => _error =
              'تعذّر البحث. قد تكون الخدمة مشغولة؛ انتظر دقيقة وأعد المحاولة.',
        );
      }
    } finally {
      if (mounted && token == _revision) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _revision++;
    widget.controller.removeListener(_changed);
    _repository.cancel();
    if (widget.repository == null) _repository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppPalette.of(context).background,
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: DirectoryHeader(
                title: 'المساجد القريبة',
                subtitle: 'مساجد حول الموقع الذي تختاره',
                onBack: () => Navigator.maybePop(context),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  _notice(
                    context,
                    'الموقع: ${_place?.label ?? 'غير محدد'}. بالضغط على البحث تُرسل الإحداثيات المختارة إلى Overpass / OpenStreetMap للبحث ضمن 3 كم. لا يبدأ الطلب تلقائياً.',
                  ),
                  FilledButton.icon(
                    onPressed: _place == null || _busy ? null : _search,
                    icon: const Icon(Icons.search),
                    label: Text(
                      _busy ? 'جارٍ البحث…' : 'البحث في OpenStreetMap',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PrayerSettingsPage(controller: widget.controller),
                      ),
                    ),
                    child: const Text('تحديد الموقع'),
                  ),
                  if (_error != null) _notice(context, _error!),
                  if (_items?.isEmpty == true)
                    _notice(
                      context,
                      'لم تُرجع الخريطة مساجد ضمن النطاق. هذا لا يعني عدم وجود مساجد على الأرض.',
                    ),
                  if (_items case final items?)
                    for (final mosque in items)
                      _panel(
                        context,
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.mosque_outlined,
                            color: AppPalette.of(context).gold,
                          ),
                          title: Text(mosque.name),
                          subtitle: Text(
                            '${(mosque.distance / 1000).toStringAsFixed(2)} كم بخط مستقيم؛ ليست مسافة طريق',
                          ),
                          trailing: IconButton(
                            tooltip: 'فتح الخريطة',
                            onPressed: () =>
                                widget.controller.openMap(mosque.mapUrl),
                            icon: const Icon(Icons.open_in_new),
                          ),
                        ),
                      ),
                  _notice(
                    context,
                    '© OpenStreetMap contributors • ODbL. قائمة محدودة حتى100 نتيجة، تُرتّب بالمسافة المستقيمة ضمن النتائج المسترجعة. قد تكون البيانات ناقصة أو قديمة؛ لا معلومات مفترضة عن مواعيد الفتح أو الخدمات. الخدمة العامة بلا ضمان توافر؛ يلزم اعتماد استضافة مناسبة قبل الإطلاق الواسع.',
                  ),
                  TextButton(
                    onPressed: () => widget.controller.openMap(
                      Uri.https('www.openstreetmap.org', '/copyright'),
                    ),
                    child: const Text('المصدر والترخيص — OpenStreetMap'),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
