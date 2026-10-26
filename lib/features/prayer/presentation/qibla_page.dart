part of 'prayer_page.dart';

class QiblaPage extends StatefulWidget {
  const QiblaPage({
    super.key,
    required this.controller,
    this.active = true,
    this.heading,
    this.beforeAudio,
    this.enableReminders,
  });
  final PrayerController controller;
  final bool active;
  final HeadingController? heading;
  final Future<void> Function()? beforeAudio;
  final Future<bool> Function()? enableReminders;
  @override
  State<QiblaPage> createState() => _QiblaPageState();
}

class _QiblaPageState extends State<QiblaPage>
    with WidgetsBindingObserver, RouteAware {
  late final HeadingController _heading = widget.heading ?? HeadingController();
  bool _visible = true, _foreground = true, _aligned = false, _extra = false;
  ModalRoute<dynamic>? _route;
  PrayerLocation? _place;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    _heading.addListener(_direction);
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
    if (_place != widget.controller.config.location) _sync();
    if (mounted) setState(() {});
  }

  void _direction() {
    var next = false;
    try {
      if (_heading.usable &&
          _place != null &&
          widget.active &&
          _visible &&
          _foreground) {
        final error = headingDifference(
          qiblaBearing(_place!),
          _heading.degrees!,
        ).abs();
        next = error <= (_aligned ? 8 : 5);
      }
    } catch (_) {
      /* Direction is undefined very close to the Kaaba. */
    }
    if (_aligned != next && mounted) setState(() => _aligned = next);
  }

  void _sync() {
    final location = widget.controller.config.location;
    if (!widget.active || !_visible || !_foreground || location == null) {
      _heading.stop();
      _place = null;
      _aligned = false;
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
    _heading.removeListener(_direction);
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
        listenable: _heading,
        builder: (context, _) {
          final c = widget.controller,
              place = c.config.location,
              p = AppPalette.of(context);
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
          final difference = show
              ? headingDifference(bearing, _heading.degrees!)
              : null;
          final local = place == null
              ? c.now
              : tz.TZDateTime.from(c.now, place.timeZone);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: DirectoryHeader(
                  title: 'بوصلة القبلة',
                  subtitle: 'حيث يتّجه قلبك',
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 18,
                                color: p.gold,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  place?.label ?? 'الموقع غير متاح',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: p.heading,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.config.method.label,
                            style: TextStyle(color: p.muted, fontSize: 12),
                          ),
                          const SizedBox(height: 18),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 340),
                            child: QiblaDial(
                              angle: difference,
                              aligned: show && _aligned,
                            ),
                          ),
                          AnimatedContainer(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 240),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: show && _aligned ? p.paleTeal : p.notice,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Text(
                              show
                                  ? _aligned
                                        ? 'استقبل القبلة'
                                        : 'اتجه ${difference! > 0 ? 'يمينًا' : 'يسارًا'} ${difference.abs().round()}°'
                                  : place == null
                                  ? 'اختر موقعك أو اسمح بتحديده لعرض زاوية القبلة.'
                                  : bearing == null
                                  ? 'الاتجاه غير محدد قرب الكعبة'
                                  : _heading.error ??
                                        (!_heading.trueNorth
                                            ? 'نحتاج قراءة الشمال الحقيقي. تحقق من إذن الموقع وتوفر الحساس.'
                                            : 'الدقة منخفضة — حرّك الجهاز بشكل 8 بعيداً عن المعادن.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: show && _aligned
                                    ? p.tealHeading
                                    : p.heading,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (place != null) ...[
                            const SizedBox(height: 18),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 18,
                              runSpacing: 8,
                              children: [
                                Text(
                                  'إلى الكعبة ${(distanceMetres(place.latitude, place.longitude, 21.4225241, 39.8261818) / 1000).toStringAsFixed(1)} كم',
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                if (bearing != null)
                                  Text(
                                    'القبلة ${bearing.toStringAsFixed(1)}° من الشمال الحقيقي',
                                    style: TextStyle(
                                      color: p.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              show
                                  ? 'قراءة الحساس متاحة — تحقق من المعايرة'
                                  : 'لا يوجد اتجاه حي موثوق حاليًا',
                              style: TextStyle(color: p.muted, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _panel(
                      context,
                      Column(
                        children: [
                          Text(
                            prayerGregorianDate(local),
                            style: TextStyle(
                              color: p.heading,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(c.hijriLabel, style: TextStyle(color: p.muted)),
                          if (c.today case final day?) ...[
                            const SizedBox(height: 16),
                            for (final moment in day.moments)
                              _PrayerTimeRow(
                                controller: c,
                                moment: moment,
                                beforeAudio: widget.beforeAudio,
                                enableReminders: widget.enableReminders,
                              ),
                            TextButton.icon(
                              onPressed: () => setState(() => _extra = !_extra),
                              icon: Icon(
                                _extra ? Icons.expand_less : Icons.expand_more,
                              ),
                              label: const Text('أوقات أخرى'),
                            ),
                            if (_extra) ...[
                              for (final item in additionalPrayerTimes(
                                c.config,
                                c.now,
                              ).entries)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(child: Text(item.key)),
                                      Text(
                                        prayerClockLabel(item.value),
                                        textDirection: TextDirection.ltr,
                                      ),
                                    ],
                                  ),
                                ),
                              const Text(
                                'الضحى تقدير بعد الشروق بـ20 دقيقة. منتصف الليل والثلث الأخير من المغرب إلى الفجر التالي.',
                                style: TextStyle(fontSize: 11),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            if (c.upcoming != null) ...[
                              const Divider(),
                              Text(
                                'الصلاة القادمة: ${c.upcoming!.name.label}',
                                style: TextStyle(color: p.tealHeading),
                              ),
                              Text(
                                c.countdown,
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.bold,
                                  color: p.tealHeading,
                                ),
                              ),
                            ],
                          ] else
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('حدّد الموقع لعرض مواقيت الصلاة'),
                            ),
                        ],
                      ),
                    ),
                    if (c.error case final error?) _notice(context, error),
                    if (c.calculationError case final error?)
                      _notice(context, error),
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
                      'ضع الهاتف مستوياً بعيداً عن المغناطيس والمعادن. حرّكه بشكل 8 للمعايرة. المواقيت محسوبة حسب الموقع والطريقة؛ راجعها مع الجهة المحلية.',
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

class _PrayerTimeRow extends StatelessWidget {
  const _PrayerTimeRow({
    required this.controller,
    required this.moment,
    this.beforeAudio,
    this.enableReminders,
  });
  final PrayerController controller;
  final PrayerMoment moment;
  final Future<void> Function()? beforeAudio;
  final Future<bool> Function()? enableReminders;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context),
        alert = controller.config.alert(moment.name);
    final enabled =
        controller.config.notifications &&
        controller.config.enabledPrayers.contains(moment.name.name);
    final next = controller.upcoming?.time == moment.time;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: next ? p.paleTeal : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              moment.name.label,
              style: TextStyle(
                fontWeight: next ? FontWeight.bold : FontWeight.normal,
                color: p.heading,
              ),
            ),
          ),
          IconButton(
            tooltip: 'إعدادات ${moment.name.label}',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => PrayerAlertPage(
                  controller: controller,
                  prayer: moment.name,
                  beforeAudio: beforeAudio,
                  enableReminders: enableReminders,
                ),
              ),
            ),
            icon: Icon(
              !enabled
                  ? Icons.notifications_off_outlined
                  : switch (alert.mode) {
                      PrayerAlertMode.adhan => Icons.volume_up_outlined,
                      PrayerAlertMode.chime =>
                        Icons.notifications_active_outlined,
                      PrayerAlertMode.vibration => Icons.vibration,
                      PrayerAlertMode.silent => Icons.notifications_none,
                    },
              color: enabled ? p.tealHeading : p.muted,
              size: 20,
            ),
          ),
          Expanded(
            child: Text(
              prayerClockLabel(moment.time),
              textAlign: TextAlign.end,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: p.heading,
                fontWeight: next ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
