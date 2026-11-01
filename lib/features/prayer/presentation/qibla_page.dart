part of 'prayer_page.dart';

class QiblaPage extends StatefulWidget {
  const QiblaPage({
    super.key,
    required this.controller,
    this.active = true,
    this.heading,
    this.beforeAudio,
    this.enableReminders,
    this.onOpenRoute,
  });
  final ValueChanged<String>? onOpenRoute;
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

  void _openAdhanSettings() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => PrayerAdhanSettingsPage(
        controller: widget.controller,
        onOpenRoute: widget.onOpenRoute,
        beforeAudio: widget.beforeAudio,
        enableReminders: widget.enableReminders,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection:
        LocalizationScope.maybeOf(context)?.language.direction ??
        TextDirection.rtl,
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
                child: Stack(
                  children: [
                    DirectoryHeader(
                      title: context.prayerLabel('بوصلة القبلة'),
                      subtitle: context.prayerLabel('حيث يتّجه قلبك'),
                      onBack: () => Navigator.maybePop(context),
                    ),
                    Positioned(
                      right: 16,
                      top: MediaQuery.paddingOf(context).top + 18,
                      child: Material(
                        color: p.surface,
                        shape: const CircleBorder(),
                        child: IconButton(
                          key: const ValueKey('qibla-adhan-settings'),
                          tooltip: context.prayerLabel('إعدادات الأذان'),
                          onPressed: _openAdhanSettings,
                          icon: Icon(Icons.tune_rounded, color: p.tealHeading),
                        ),
                      ),
                    ),
                  ],
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
                                  place?.label ??
                                      context.prayerLabel('الموقع غير متاح'),
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
                            c.config.method.displayLabel(context),
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
                                        ? context.prayerLabel('استقبل القبلة')
                                        : context.tr(
                                            'prayer.turn',
                                            args: {
                                              'direction': context.tr(
                                                difference! > 0
                                                    ? 'prayer.right'
                                                    : 'prayer.left',
                                              ),
                                              'degrees': difference
                                                  .abs()
                                                  .round(),
                                            },
                                          )
                                  : place == null
                                  ? context.prayerLabel(
                                      'اختر موقعك أو اسمح بتحديده لعرض زاوية القبلة.',
                                    )
                                  : bearing == null
                                  ? context.prayerLabel(
                                      'الاتجاه غير محدد قرب الكعبة',
                                    )
                                  : (_heading.error == null
                                            ? null
                                            : context.prayerLabel(
                                                _heading.error!,
                                              )) ??
                                        (!_heading.trueNorth
                                            ? context.prayerLabel(
                                                'نحتاج قراءة الشمال الحقيقي. تحقق من إذن الموقع وتوفر الحساس.',
                                              )
                                            : context.prayerLabel(
                                                'الدقة منخفضة — حرّك الجهاز بشكل 8 بعيداً عن المعادن.',
                                              )),
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
                                  context.tr(
                                    'prayer.kaabaDistance',
                                    args: {
                                      'distance':
                                          (distanceMetres(
                                                    place.latitude,
                                                    place.longitude,
                                                    21.4225241,
                                                    39.8261818,
                                                  ) /
                                                  1000)
                                              .toStringAsFixed(1),
                                    },
                                  ),
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                if (bearing != null)
                                  Text(
                                    context.tr(
                                      'prayer.bearing',
                                      args: {
                                        'degrees': bearing.toStringAsFixed(1),
                                      },
                                    ),
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
                                  ? context.prayerLabel(
                                      'قراءة الحساس متاحة — تحقق من المعايرة',
                                    )
                                  : context.prayerLabel(
                                      'لا يوجد اتجاه حي موثوق حاليًا',
                                    ),
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
                            LocalizationScope.maybeOf(
                                  context,
                                )?.formats.gregorianDate(local) ??
                                prayerGregorianDate(local),
                            style: TextStyle(
                              color: p.heading,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            prayerHijriInterfaceLabel(context, c),
                            style: TextStyle(color: p.muted),
                          ),
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
                              label: Text(context.prayerLabel('أوقات أخرى')),
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
                              Text(
                                context.prayerLabel(
                                  'الضحى تقدير بعد الشروق بـ20 دقيقة. منتصف الليل والثلث الأخير من المغرب إلى الفجر التالي.',
                                ),
                                style: TextStyle(fontSize: 11),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            if (c.upcoming != null) ...[
                              const Divider(),
                              Text(
                                context.tr(
                                  'prayer.next',
                                  args: {
                                    'prayer': c.upcoming!.name.displayLabel(
                                      context,
                                    ),
                                  },
                                ),
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
                            Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                context.prayerLabel(
                                  'حدّد الموقع لعرض مواقيت الصلاة',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (c.error case final error?) _notice(context, error),
                    if (c.locationNotice case final notice?)
                      _notice(context, notice),
                    if (c.calculationError case final error?)
                      _notice(context, error),
                    FilledButton.icon(
                      onPressed: c.locating ? null : c.locate,
                      icon: c.locating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              place == null ? Icons.my_location : Icons.refresh,
                            ),
                      label: Text(
                        c.locating
                            ? context.prayerLabel('جارٍ تحديد الموقع…')
                            : place == null
                            ? context.prayerLabel(
                                'السماح بالموقع / إعادة المحاولة',
                              )
                            : context.prayerLabel('تحديث الموقع'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _openAdhanSettings,
                      child: Text(context.prayerLabel('إعدادات الأذان')),
                    ),
                    if (place != null)
                      TextButton(
                        onPressed: () {
                          _place = null;
                          _sync();
                          setState(() {});
                        },
                        child: Text(context.prayerLabel('إعادة قراءة الحساس')),
                      ),
                    _notice(
                      context,
                      context.prayerLabel(
                        'ضع الهاتف مستوياً بعيداً عن المغناطيس والمعادن. حرّكه بشكل 8 للمعايرة. المواقيت محسوبة حسب الموقع والطريقة؛ راجعها مع الجهة المحلية.',
                      ),
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
              moment.name.displayLabel(context),
              style: TextStyle(
                fontWeight: next ? FontWeight.bold : FontWeight.normal,
                color: p.heading,
              ),
            ),
          ),
          IconButton(
            tooltip: context.tr(
              'prayer.alertFor',
              fallback: 'إعدادات ${moment.name.label}',
              args: {'prayer': moment.name.displayLabel(context)},
            ),
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
              LocalizationScope.maybeOf(
                    context,
                  )?.formats.clock24(moment.time) ??
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
