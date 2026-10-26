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
              title: const Text('المنطقة الزمنية'),
              content: SizedBox(
                width: 420,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'بحث مثل Asia/Hebron',
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
                  child: const Text('إلغاء'),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('حُفظت إعدادات الصلاة')));
      }
    } catch (_) {
      if (mounted && owner == _scope) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تحقق من الإحداثيات والمنطقة الزمنية')),
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
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppPalette.of(context).background,
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: DirectoryHeader(
                title: 'إعدادات الصلاة',
                subtitle: 'الموقع والحساب والتنبيهات',
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
                            const Text(
                              'الموقع المعتمد',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
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
                              icon: const Icon(Icons.my_location),
                              label: Text(
                                widget.controller.locating
                                    ? 'جارٍ تحديد الموقع…'
                                    : 'تحديد موقع الجهاز بإذن منك',
                              ),
                            ),
                            TextButton(
                              onPressed: widget.controller.openSettings,
                              child: const Text('فتح أذونات الموقع في الجهاز'),
                            ),
                            if (widget.controller.config.location
                                case final place?)
                              if (place.fromDevice)
                                Text(
                                  'آخر قياس محفوظ: ${place.measuredAt?.toLocal().toString().split('.').first ?? 'غير متاح'} • دقة تقريبية ${place.accuracy?.round() ?? 0} متر',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppPalette.of(context).muted,
                                  ),
                                ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _label,
                              decoration: const InputDecoration(
                                labelText: 'اسم الموقع اليدوي',
                              ),
                              maxLength: 100,
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'اكتب اسماً للموقع'
                                  : null,
                            ),
                            for (final entry in [
                              (_lat, 'خط العرض (-90 إلى 90)', 90),
                              (_lng, 'خط الطول (-180 إلى 180)', 180),
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
                                  labelText: entry.$2,
                                ),
                                validator: (value) {
                                  final n = double.tryParse(
                                    value?.trim() ?? '',
                                  );
                                  return n == null ||
                                          !n.isFinite ||
                                          n.abs() > entry.$3
                                      ? 'أدخل إحداثية صحيحة'
                                      : null;
                                },
                              ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('المنطقة الزمنية للموقع'),
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
                                    tz.timeZoneDatabase.locations.containsKey(
                                      zone,
                                    )) {
                                  setState(() => _zone = zone);
                                }
                              },
                              child: const Text(
                                'استخدام المنطقة الزمنية الحالية للجهاز',
                              ),
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
                              decoration: const InputDecoration(
                                labelText: 'طريقة الحساب',
                              ),
                              items: [
                                for (final method in PrayerMethod.values)
                                  DropdownMenuItem(
                                    value: method,
                                    child: Text(method.label),
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
                              title: const Text('حساب العصر الحنفي'),
                              subtitle: const Text(
                                'عند الإيقاف يستخدم حساب العصر الشافعي',
                              ),
                              value: _draft.hanafi,
                              onChanged: (v) => setState(
                                () => _draft = _draft.copyWith(hanafi: v),
                              ),
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _draft.highLatitude,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'خطوط العرض العالية',
                              ),
                              items: [
                                for (final e in const {
                                  'recommended': 'القاعدة الموصى بها للموقع',
                                  'middle': 'منتصف الليل',
                                  'seventh': 'سُبع الليل',
                                  'angle': 'حسب زاوية الشفق',
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
                            const Text(
                              'الطرق حسابية وقد تختلف عن التوقيت الرسمي. أم القرى: يمكن زيادة تصحيح العشاء 30 دقيقة في رمضان حسب اعتمادك المحلي.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      _panel(
                        context,
                        Column(
                          children: [
                            const Text(
                              'تصحيح المواقيت بالدقائق',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            for (final prayer in PrayerName.values)
                              Row(
                                children: [
                                  Expanded(child: Text(prayer.label)),
                                  IconButton(
                                    tooltip: 'نقص دقيقة ${prayer.label}',
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
                                    tooltip: 'زيادة دقيقة ${prayer.label}',
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
                      _panel(
                        context,
                        Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('تذكيرات الصلاة'),
                              value: _draft.notifications,
                              onChanged: (v) => setState(
                                () =>
                                    _draft = _draft.copyWith(notifications: v),
                              ),
                            ),
                            for (final prayer in PrayerName.values.where(
                              (p) => p != PrayerName.sunrise,
                            ))
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('تنبيه ${prayer.label}'),
                                value: _draft.enabledPrayers.contains(
                                  prayer.name,
                                ),
                                onChanged: (value) => setState(() {
                                  final selected = _draft.enabledPrayers
                                      .toSet();
                                  if (value == true) {
                                    selected.add(prayer.name);
                                  } else {
                                    selected.remove(prayer.name);
                                  }
                                  _draft = _draft.copyWith(
                                    enabledPrayers: selected.toList(),
                                  );
                                }),
                              ),
                            DropdownButtonFormField<int>(
                              initialValue: _draft.beforeMinutes,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'التذكير قبل الصلاة',
                              ),
                              items: [
                                for (final v in [0, 5, 10, 15, 20, 30, 45, 60])
                                  DropdownMenuItem(
                                    value: v,
                                    child: Text(
                                      v == 0 ? 'بدون تذكير مسبق' : '$v دقيقة',
                                    ),
                                  ),
                              ],
                              onChanged: (v) => setState(
                                () =>
                                    _draft = _draft.copyWith(beforeMinutes: v),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              initialValue: _draft.afterMinutes,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'أذكار بعد الصلاة',
                              ),
                              items: [
                                for (final v in [0, 1, 5, 10, 15, 20, 30])
                                  DropdownMenuItem(
                                    value: v,
                                    child: Text(
                                      v == 0 ? 'غير مفعّل' : 'بعد $v دقيقة',
                                    ),
                                  ),
                              ],
                              onChanged: (v) => setState(
                                () => _draft = _draft.copyWith(afterMinutes: v),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'يلزم أيضاً تفعيل التذكيرات العامة وإذن الإشعارات من إعدادات التطبيق. التنبيه بصوت النظام المختار هناك؛ ليس تلاوة أذان كاملة. نجدد المواعيد عند فتح التطبيق: Android حتى14 يوماً، وiOS ضمن سعة الطلبات المتاحة. قد يؤخر النظام الإشعار.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.check),
                        label: Text(
                          _saving ? 'جارٍ الحفظ…' : 'حفظ إعدادات الصلاة',
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final owner = _scope;
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('مسح الموقع وإعدادات الصلاة؟'),
                              content: const Text(
                                'تلغي تذكيرات الصلاة لهذا الحساب وتبقى بقية بياناتك محفوظة.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('إلغاء'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('مسح'),
                                ),
                              ],
                            ),
                          );
                          if (mounted && yes == true && owner == _scope) {
                            await widget.controller.reset();
                            if (mounted) setState(_fill);
                          }
                        },
                        child: const Text('مسح الموقع وإعدادات هذا القسم'),
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
