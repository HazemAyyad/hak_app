part of 'prayer_page.dart';

class PrayerSettingsPage extends StatefulWidget {
  const PrayerSettingsPage({super.key, required this.controller});
  final PrayerController controller;
  @override
  State<PrayerSettingsPage> createState() => _PrayerSettingsPageState();
}

class _PrayerSettingsPageState extends State<PrayerSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _label = TextEditingController(),
      _lat = TextEditingController(),
      _lng = TextEditingController();
  late PrayerConfig _draft;
  late String _scope;
  String _zone = 'Etc/UTC';
  bool _saving = false;
  BuildContext? _dialog;
  @override
  void initState() {
    super.initState();
    _scope = widget.controller.scope;
    _fill();
    widget.controller.addListener(_account);
  }

  void _fill() {
    _draft = widget.controller.config;
    final place = _draft.location;
    _label.text = place?.label ?? '';
    _lat.text = place?.latitude.toString() ?? '';
    _lng.text = place?.longitude.toString() ?? '';
    _zone = place?.zone ?? 'Etc/UTC';
  }

  void _account() {
    if (_scope != widget.controller.scope) {
      _scope = widget.controller.scope;
      if (_dialog case final dialog?) {
        if (dialog.mounted && ModalRoute.of(dialog)?.isCurrent == true) {
          Navigator.pop(dialog);
        }
        _dialog = null;
      }
      if (mounted) setState(_fill);
    }
  }

  Future<void> _pickLocation({required bool map}) async {
    final owner = _scope;
    final place = await Navigator.push<PrayerLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => PrayerLocationPicker(
          controller: widget.controller,
          initial: _draft.location,
          showMap: map,
        ),
      ),
    );
    if (!mounted || owner != _scope || place == null) return;
    setState(() {
      _draft = _draft.copyWith(location: place);
      _label.text = place.label;
      _lat.text = place.latitude.toString();
      _lng.text = place.longitude.toString();
      _zone = place.zone;
    });
  }

  Future<void> _pickZone() async {
    final owner = _scope;
    var filter = '';
    final zones = tz.timeZoneDatabase.locations.keys.toList()..sort();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        _dialog = context;
        return StatefulBuilder(
          builder: (context, setDialog) {
            final shown = zones
                .where((z) => z.toLowerCase().contains(filter.toLowerCase()))
                .toList();
            return AlertDialog(
              title: Text(context.prayerLabel('المنطقة الزمنية')),
              content: SizedBox(
                width: 420,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        labelText: context.prayerLabel('بحث مثل Asia/Hebron'),
                      ),
                      onChanged: (v) => setDialog(() => filter = v),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) => ListTile(
                          title: Text(
                            shown[i],
                            textDirection: TextDirection.ltr,
                          ),
                          onTap: () => Navigator.pop(context, shown[i]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.prayerLabel('إلغاء')),
                ),
              ],
            );
          },
        );
      },
    );
    _dialog = null;
    if (mounted && result != null && owner == _scope) {
      setState(() => _zone = result);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_saving || !_form.currentState!.validate()) return;
    if (_lat.text.isEmpty || _lng.text.isEmpty || _label.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.prayerLabel(
              'ابحث عن مدينة أو اختر موقعك على الخريطة أولًا',
            ),
          ),
        ),
      );
      return;
    }
    final owner = _scope;
    setState(() => _saving = true);
    try {
      final place = PrayerLocation(
        latitude: double.parse(_lat.text.trim()),
        longitude: double.parse(_lng.text.trim()),
        zone: _zone,
        label: _label.text.trim(),
      );
      final old = widget.controller.config.location;
      final keepGps =
          old != null &&
          old.latitude == place.latitude &&
          old.longitude == place.longitude &&
          old.zone == place.zone &&
          old.label == place.label;
      final saved = await widget.controller.save(
        _draft.copyWith(location: keepGps ? old : place),
      );
      if (mounted && owner == _scope && saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.prayerLabel('حُفظت إعدادات الصلاة'))),
        );
      }
    } catch (_) {
      if (mounted && owner == _scope) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.prayerLabel('تحقق من الإحداثيات والمنطقة الزمنية'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_account);
    _label.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection:
        LocalizationScope.maybeOf(context)?.language.direction ??
        TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppPalette.of(context).background,
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: DirectoryHeader(
                title: context.prayerLabel('الموقع وحساب المواقيت'),
                subtitle: context.prayerLabel('المدينة والدولة وطريقة الحساب'),
                onBack: () => Navigator.maybePop(context),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
              sliver: SliverToBoxAdapter(
                child: Form(
                  key: _form,
                  child: Column(
                    children: [
                      if (widget.controller.error case final error?)
                        _notice(context, error),
                      _panel(
                        context,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              context.prayerLabel('الموقع المعتمد'),
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (widget.controller.config.location
                                case final location?)
                              Text(
                                location.city != null &&
                                        location.country != null
                                    ? '${location.city}، ${location.country}'
                                    : location.label,
                                key: const ValueKey('saved-prayer-place'),
                                style: TextStyle(
                                  color: AppPalette.of(context).tealHeading,
                                ),
                              ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: widget.controller.locating
                                  ? null
                                  : () async {
                                      final owner = _scope;
                                      await widget.controller.locate();
                                      if (mounted &&
                                          owner == _scope &&
                                          widget.controller.error == null) {
                                        setState(_fill);
                                      }
                                    },
                              icon: widget.controller.locating
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      widget.controller.config.location == null
                                          ? Icons.my_location
                                          : Icons.refresh,
                                    ),
                              label: Text(
                                widget.controller.locating
                                    ? context.prayerLabel('جارٍ تحديد الموقع…')
                                    : widget.controller.config.location == null
                                    ? context.prayerLabel(
                                        'تحديد موقع الجهاز بإذن منك',
                                      )
                                    : context.prayerLabel('تحديث موقع الجهاز'),
                              ),
                            ),
                            if (widget.controller.locationNotice
                                case final notice?)
                              Text(
                                notice,
                                style: TextStyle(
                                  color: AppPalette.of(context).tealHeading,
                                  fontSize: 12,
                                ),
                              ),
                            Text(
                              context.prayerLabel(
                                'لتسمية المدينة والدولة نستخدم خدمة الأماكن في نظام الجهاز. قد تحتاج إلى الإنترنت.',
                              ),
                              style: TextStyle(
                                color: AppPalette.of(context).muted,
                                fontSize: 11,
                              ),
                            ),
                            TextButton(
                              onPressed: widget.controller.openSettings,
                              child: Text(
                                context.prayerLabel(
                                  'فتح أذونات الموقع في الجهاز',
                                ),
                              ),
                            ),
                            if (widget.controller.config.location
                                case final place?)
                              if (place.fromDevice)
                                Text(
                                  context.tr(
                                    'prayer.lastMeasurement',
                                    args: {
                                      'date': place.measuredAt == null
                                          ? context.prayerLabel('غير متاح')
                                          : LocalizationScope.maybeOf(
                                                  context,
                                                )?.formats.gregorianDateTime(
                                                  place.measuredAt!.toLocal(),
                                                ) ??
                                                place.measuredAt!
                                                    .toLocal()
                                                    .toString()
                                                    .split('.')
                                                    .first,
                                      'accuracy':
                                          LocalizationScope.maybeOf(
                                            context,
                                          )?.formats.number(
                                            place.accuracy?.round() ?? 0,
                                          ) ??
                                          '${place.accuracy?.round() ?? 0}',
                                    },
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppPalette.of(context).muted,
                                  ),
                                ),
                            const SizedBox(height: 8),
                            if (_draft.location case final place?)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.place_outlined,
                                  color: AppPalette.of(context).tealHeading,
                                ),
                                title: Text(place.label),
                                subtitle: Text(
                                  place.zone,
                                  textDirection: TextDirection.ltr,
                                ),
                              ),
                            Text(
                              context.prayerLabel('الاختيار اليدوي'),
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => _pickLocation(map: false),
                              icon: const Icon(Icons.search),
                              label: Text(
                                context.prayerLabel('بحث عن دولة أو مدينة'),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _pickLocation(map: true),
                              icon: const Icon(Icons.map_outlined),
                              label: Text(
                                context.prayerLabel('تحديد نقطة على الخريطة'),
                              ),
                            ),
                            Text(
                              context.prayerLabel(
                                'بعد اختيار الموقع اضغط «حفظ إعدادات الصلاة».',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppPalette.of(context).muted,
                              ),
                            ),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                context.prayerLabel(
                                  'ضبط الإحداثيات والمنطقة الزمنية يدويًا',
                                ),
                                style: TextStyle(fontSize: 12),
                              ),
                              children: [
                                TextFormField(
                                  controller: _label,
                                  decoration: InputDecoration(
                                    labelText: context.prayerLabel(
                                      'اسم الموقع اليدوي',
                                    ),
                                  ),
                                  maxLength: 100,
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? context.prayerLabel('اكتب اسماً للموقع')
                                      : null,
                                ),
                                for (final entry in [
                                  (
                                    _lat,
                                    context.prayerLabel(
                                      'خط العرض (-90 إلى 90)',
                                    ),
                                    90,
                                  ),
                                  (
                                    _lng,
                                    context.prayerLabel(
                                      'خط الطول (-180 إلى 180)',
                                    ),
                                    180,
                                  ),
                                ])
                                  TextFormField(
                                    controller: entry.$1,
                                    textDirection: TextDirection.ltr,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                          signed: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: context.prayerLabel(entry.$2),
                                    ),
                                    validator: (value) {
                                      final n = double.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      return n == null ||
                                              !n.isFinite ||
                                              n.abs() > entry.$3
                                          ? context.prayerLabel(
                                              'أدخل إحداثية صحيحة',
                                            )
                                          : null;
                                    },
                                  ),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    context.prayerLabel(
                                      'المنطقة الزمنية للموقع',
                                    ),
                                  ),
                                  subtitle: Text(
                                    _zone,
                                    textDirection: TextDirection.ltr,
                                  ),
                                  trailing: const Icon(Icons.chevron_left),
                                  onTap: _pickZone,
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final owner = _scope;
                                    final state = await widget.controller
                                        .deviceStatus();
                                    final zone = state['zone'];
                                    if (mounted &&
                                        owner == _scope &&
                                        zone is String &&
                                        tz.timeZoneDatabase.locations
                                            .containsKey(zone)) {
                                      setState(() => _zone = zone);
                                    }
                                  },
                                  child: Text(
                                    context.prayerLabel(
                                      'استخدام المنطقة الزمنية الحالية للجهاز',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _panel(
                        context,
                        Column(
                          children: [
                            DropdownButtonFormField<PrayerMethod>(
                              initialValue: _draft.method,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: context.prayerLabel('طريقة الحساب'),
                              ),
                              items: [
                                for (final method in PrayerMethod.values)
                                  DropdownMenuItem(
                                    value: method,
                                    child: Text(method.displayLabel(context)),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(
                                    () =>
                                        _draft = _draft.copyWith(method: value),
                                  );
                                }
                              },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                context.prayerLabel('حساب العصر الحنفي'),
                              ),
                              subtitle: Text(
                                context.prayerLabel(
                                  'عند الإيقاف يستخدم حساب العصر الشافعي',
                                ),
                              ),
                              value: _draft.hanafi,
                              onChanged: (v) => setState(
                                () => _draft = _draft.copyWith(hanafi: v),
                              ),
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _draft.highLatitude,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: context.prayerLabel(
                                  'خطوط العرض العالية',
                                ),
                              ),
                              items: [
                                for (final e in {
                                  'recommended': context.prayerLabel(
                                    'القاعدة الموصى بها للموقع',
                                  ),
                                  'middle': context.prayerLabel('منتصف الليل'),
                                  'seventh': context.prayerLabel('سُبع الليل'),
                                  'angle': context.prayerLabel(
                                    'حسب زاوية الشفق',
                                  ),
                                }.entries)
                                  DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(
                                    () => _draft = _draft.copyWith(
                                      highLatitude: v,
                                    ),
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.prayerLabel(
                                'الطرق حسابية وقد تختلف عن التوقيت الرسمي. أم القرى: يمكن زيادة تصحيح العشاء 30 دقيقة في رمضان حسب اعتمادك المحلي.',
                              ),
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      _panel(
                        context,
                        Column(
                          children: [
                            Text(
                              context.prayerLabel('تصحيح المواقيت بالدقائق'),
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            for (final prayer in PrayerName.values)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(prayer.displayLabel(context)),
                                  ),
                                  IconButton(
                                    tooltip: context.tr(
                                      'prayer.subtractMinute',
                                      args: {
                                        'prayer': prayer.displayLabel(context),
                                      },
                                    ),
                                    onPressed: () => setState(
                                      () => _draft = _draft.copyWith(
                                        adjustments: {
                                          ..._draft.adjustments,
                                          prayer.name:
                                              ((_draft.adjustments[prayer
                                                              .name] ??
                                                          0) -
                                                      1)
                                                  .clamp(-30, 30),
                                        },
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 42,
                                    child: Text(
                                      '${_draft.adjustments[prayer.name] ?? 0}',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: context.tr(
                                      'prayer.addMinute',
                                      args: {
                                        'prayer': prayer.displayLabel(context),
                                      },
                                    ),
                                    onPressed: () => setState(
                                      () => _draft = _draft.copyWith(
                                        adjustments: {
                                          ..._draft.adjustments,
                                          prayer.name:
                                              ((_draft.adjustments[prayer
                                                              .name] ??
                                                          0) +
                                                      1)
                                                  .clamp(-30, 30),
                                        },
                                      ),
                                    ),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check),
                        label: Text(
                          _saving
                              ? context.prayerLabel('جارٍ الحفظ…')
                              : context.prayerLabel('حفظ إعدادات الصلاة'),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final owner = _scope;
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(
                                context.prayerLabel(
                                  'مسح الموقع وإعدادات الصلاة؟',
                                ),
                              ),
                              content: Text(
                                context.prayerLabel(
                                  'تلغي تذكيرات الصلاة لهذا الحساب وتبقى بقية بياناتك محفوظة.',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(context.prayerLabel('إلغاء')),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(context.prayerLabel('مسح')),
                                ),
                              ],
                            ),
                          );
                          if (mounted && yes == true && owner == _scope) {
                            await widget.controller.reset();
                            if (mounted) setState(_fill);
                          }
                        },
                        child: Text(
                          context.prayerLabel('مسح الموقع وإعدادات هذا القسم'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
