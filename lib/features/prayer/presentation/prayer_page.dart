import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../app_appearance.dart';
import '../../../navigation/more_page.dart';
import '../data/prayer_controller.dart';
import '../data/prayer_models.dart';
import '../data/heading_controller.dart';
import '../data/mosque_repository.dart';

part 'prayer_settings.dart';

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
  const PrayerPage({super.key, required this.controller});
  final PrayerController controller;
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
                            ListTile(
                              title: Text(moment.name.label),
                              trailing: Text(
                                moment.label,
                                textDirection: TextDirection.ltr,
                              ),
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
                        builder: (_) =>
                            PrayerSettingsPage(controller: controller),
                      ),
                    ),
                    icon: const Icon(Icons.tune),
                    label: const Text('الموقع والحساب والتنبيهات'),
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

class QiblaPage extends StatefulWidget {
  const QiblaPage({
    super.key,
    required this.controller,
    this.active = true,
    this.heading,
  });
  final PrayerController controller;
  final bool active;
  final HeadingController? heading;
  @override
  State<QiblaPage> createState() => _QiblaPageState();
}

class _QiblaPageState extends State<QiblaPage>
    with WidgetsBindingObserver, RouteAware {
  late final HeadingController _heading = widget.heading ?? HeadingController();
  bool _visible = true, _foreground = true;
  ModalRoute<dynamic>? _route;
  PrayerLocation? _place;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      prayerRoutes.unsubscribe(this);
      _route = route;
      if (route != null) prayerRoutes.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(QiblaPage old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _changed() {
    if (_place != widget.controller.config.location) {
      _sync();
      if (mounted) setState(() {});
    }
  }

  void _sync() {
    final location = widget.controller.config.location;
    if (!widget.active || !_visible || !_foreground || location == null) {
      _heading.stop();
      _place = null;
      return;
    }
    if (_place != location) {
      _place = location;
      _heading.start(location);
    }
  }

  @override
  void didPushNext() {
    _visible = false;
    _sync();
  }

  @override
  void didPopNext() {
    _visible = true;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    prayerRoutes.unsubscribe(this);
    widget.controller.removeListener(_changed);
    _heading.stop();
    if (widget.heading == null) _heading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Material(
      color: AppPalette.of(context).background,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.controller, _heading]),
        builder: (context, _) {
          final c = widget.controller, place = c.config.location;
          double? bearing;
          try {
            if (place != null) bearing = qiblaBearing(place);
          } catch (_) {}
          final show =
              bearing != null &&
              _heading.usable &&
              widget.active &&
              _visible &&
              _foreground;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: DirectoryHeader(
                  title: 'بوصلة القبلة',
                  subtitle: 'اتجاهك إلى الطاعة',
                  onBack: () => Navigator.maybePop(context),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    _panel(
                      context,
                      Column(
                        children: [
                          if (place == null) ...[
                            Icon(
                              Icons.explore_outlined,
                              size: 70,
                              color: AppPalette.of(context).gold,
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'الموقع غير متاح',
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'اختر موقعك أو اسمح بتحديده لعرض زاوية القبلة.',
                              textAlign: TextAlign.center,
                            ),
                          ] else ...[
                            Text(
                              place.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Semantics(
                              container: true,
                              label: show
                                  ? 'اتجاه القبلة من قراءة الحساس'
                                  : 'لا يوجد سهم اتجاه حي',
                              child: SizedBox.square(
                                dimension: 250,
                                child: CustomPaint(
                                  painter: _CompassPainter(
                                    show
                                        ? headingDifference(
                                                bearing,
                                                _heading.degrees!,
                                              ) *
                                              math.pi /
                                              180
                                        : null,
                                    AppPalette.of(context).tealHeading,
                                    AppPalette.of(context).gold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              bearing == null
                                  ? 'الاتجاه غير محدد قرب الكعبة'
                                  : 'القبلة ${bearing.toStringAsFixed(1)}° من الشمال الحقيقي',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              show
                                  ? 'قراءة الحساس متاحة — تحقق من المعايرة'
                                  : _heading.error ??
                                        (!_heading.trueNorth
                                            ? 'نحتاج قراءة الشمال الحقيقي. تحقق من إذن الموقع وتوفر الحساس.'
                                            : 'الدقة منخفضة — حرّك الجهاز بشكل 8 بعيداً عن المعادن.'),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (c.error case final error?) _notice(context, error),
                    FilledButton.icon(
                      onPressed: c.locating ? null : c.locate,
                      icon: const Icon(Icons.my_location),
                      label: Text(
                        c.locating
                            ? 'جارٍ تحديد الموقع…'
                            : 'السماح بالموقع / إعادة المحاولة',
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => PrayerSettingsPage(controller: c),
                        ),
                      ),
                      child: const Text('تحديد الموقع يدوياً وإعدادات الصلاة'),
                    ),
                    if (place != null)
                      TextButton(
                        onPressed: () {
                          _place = null;
                          _sync();
                          setState(() {});
                        },
                        child: const Text('إعادة قراءة الحساس'),
                      ),
                    _notice(
                      context,
                      'ضع الهاتف مستوياً بعيداً عن المغناطيس والمعادن. زاوية الموقع المحسوبة مستقلة عن جودة البوصلة. استخدم موقعك الفعلي؛ اختيار موقع بعيد يغيّر القبلة والمواقيت.',
                    ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _CompassPainter extends CustomPainter {
  const _CompassPainter(this.angle, this.teal, this.gold);
  final double? angle;
  final Color teal, gold;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2),
        r = size.shortestSide * .43;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = gold;
    canvas.drawCircle(center, r, paint);
    canvas.drawCircle(
      center,
      r * .86,
      paint..color = teal.withValues(alpha: .2),
    );
    for (var i = 0; i < 60; i++) {
      final a = i * math.pi / 30;
      final inner = r - (i % 5 == 0 ? 15 : 6);
      canvas.drawLine(
        center + Offset(math.sin(a) * inner, -math.cos(a) * inner),
        center + Offset(math.sin(a) * r, -math.cos(a) * r),
        paint..color = i % 5 == 0 ? gold : teal.withValues(alpha: .3),
      );
    }
    if (angle != null) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle!);
      canvas.drawPath(
        Path()
          ..moveTo(0, -r * .7)
          ..lineTo(-18, 28)
          ..lineTo(0, 15)
          ..lineTo(18, 28)
          ..close(),
        Paint()..color = teal,
      );
      canvas.restore();
    }
    canvas.drawCircle(center, 7, Paint()..color = gold);
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.angle != angle || old.teal != teal || old.gold != gold;
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
