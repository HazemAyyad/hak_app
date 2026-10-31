import '../../../core/localization/app_localization.dart';
import '../../../core/localization/ui_text.dart';
import 'prayer_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app_appearance.dart';
import '../data/place_catalog.dart';
import '../data/prayer_controller.dart';
import '../data/prayer_models.dart';

class PrayerLocationPicker extends StatefulWidget {
  const PrayerLocationPicker({
    super.key,
    required this.controller,
    this.initial,
    this.showMap = false,
    this.catalogLoader = PlaceCatalog.load,
    this.zoneAt = prayerZoneAt,
    this.tileProvider,
  });
  final PrayerController controller;
  final PrayerLocation? initial;
  final bool showMap;
  final Future<PlaceCatalog> Function() catalogLoader;
  final Future<String?> Function(double, double) zoneAt;
  final TileProvider? tileProvider;

  @override
  State<PrayerLocationPicker> createState() => _PrayerLocationPickerState();
}

class _PrayerLocationPickerState extends State<PrayerLocationPicker> {
  final _query = TextEditingController();
  final _map = MapController();
  late final String _owner;
  TileProvider? _tiles;
  PlaceCatalog? _catalog;
  PlaceCountry? _country;
  PlaceResults _results = const PlaceResults([], []);
  PrayerLocation? _selected;
  LatLng? _pin;
  String? _error;
  bool _loading = true, _resolving = false, _tileError = false;
  bool _mapOpened = false, _mapReady = false;
  int _tab = 0, _revision = 0;
  BuildContext? _creditsContext;

  @override
  void initState() {
    super.initState();
    _owner = widget.controller.scope;
    _selected = widget.initial;
    if (_selected case final place?) {
      _pin = LatLng(place.latitude, place.longitude);
    }
    _tab = widget.showMap ? 1 : 0;
    _mapOpened = widget.showMap;
    _tiles = widget.tileProvider;
    widget.controller.addListener(_accountChanged);
    _load();
  }

  void _accountChanged() {
    if (widget.controller.scope == _owner || !mounted) return;
    ++_revision;
    // Do not return a previous account's draft or dismiss a different route.
    if (_creditsContext case final dialog?) {
      if (dialog.mounted) Navigator.pop(dialog);
      _creditsContext = null;
    }
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await widget.catalogLoader();
      if (!mounted || widget.controller.scope != _owner) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
        _search();
      });
    } catch (_) {
      if (mounted && widget.controller.scope == _owner) {
        setState(() {
          _loading = false;
          _error = context.prayerLabel('تعذّر تحميل قائمة المدن. حاول مجددًا.');
        });
      }
    }
  }

  void _search() {
    _results =
        _catalog?.search(_query.text, countryCode: _country?.code) ??
        const PlaceResults([], []);
  }

  void _openTab(int tab) {
    FocusScope.of(context).unfocus();
    setState(() {
      _tab = tab;
      if (tab == 1) _mapOpened = true;
    });
    if (tab == 1 && _mapReady && _pin != null) _map.move(_pin!, 11);
  }

  void _city(PlaceCity city) {
    ++_revision;
    FocusScope.of(context).unfocus();
    setState(() {
      _resolving = false;
      _error = null;
      _selected = city.location;
      _pin = LatLng(city.latitude, city.longitude);
    });
    if (_mapReady) _map.move(_pin!, 11);
  }

  Future<void> _point(LatLng point) async {
    final revision = ++_revision;
    setState(() {
      _pin = point;
      _selected = null;
      _resolving = true;
      _error = null;
    });
    try {
      final zone = await widget.zoneAt(point.latitude, point.longitude);
      if (!mounted ||
          revision != _revision ||
          widget.controller.scope != _owner) {
        return;
      }
      if (zone == null) {
        setState(
          () => _error = context.prayerLabel(
            'لم نحدد منطقة زمنية لهذه النقطة. اختر نقطة على اليابسة أو ابحث عن مدينة.',
          ),
        );
      } else {
        setState(
          () => _selected =
              _catalog?.point(point.latitude, point.longitude, zone) ??
              PrayerLocation(
                latitude: point.latitude,
                longitude: point.longitude,
                zone: zone,
                label: 'موقع على الخريطة',
              ),
        );
      }
    } catch (_) {
      if (mounted &&
          revision == _revision &&
          widget.controller.scope == _owner) {
        setState(
          () => _error = context.prayerLabel(
            'تعذّر تحديد المنطقة الزمنية. أعد اختيار النقطة أو ابحث عن مدينة.',
          ),
        );
      }
    } finally {
      if (mounted &&
          revision == _revision &&
          widget.controller.scope == _owner) {
        setState(() => _resolving = false);
      }
    }
  }

  @override
  void dispose() {
    ++_revision;
    widget.controller.removeListener(_accountChanged);
    _query.dispose();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Directionality(
      textDirection:
          LocalizationScope.maybeOf(context)?.language.direction ??
          TextDirection.rtl,
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          backgroundColor: p.background,
          foregroundColor: p.heading,
          title: Text(context.prayerLabel('اختر موقع الصلاة')),
          leading: IconButton(
            tooltip: context.prayerLabel('رجوع'),
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_forward),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.search),
                        label: Text(context.prayerLabel('دولة أو مدينة')),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.map_outlined),
                        label: Text(context.prayerLabel('الخريطة')),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (v) => _openTab(v.first),
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: p.paleTeal,
                      selectedForegroundColor: p.tealHeading,
                      foregroundColor: p.heading,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _searchView(p),
                    _mapOpened ? _mapView(p) : const SizedBox.shrink(),
                  ],
                ),
              ),
              _selection(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchView(AppPalette p) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          key: const ValueKey('prayer-place-query'),
          controller: _query,
          onChanged: (_) => setState(_search),
          decoration: InputDecoration(
            labelText: context.prayerLabel('ابحث عن دولة أو مدينة'),
            hintText: context.prayerLabel('مثل: فلسطين، الخليل، Amman'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: context.prayerLabel('مسح البحث'),
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _query.clear();
                      _search();
                    }),
                  ),
            filled: true,
            fillColor: p.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ),
      if (_country case final country?)
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InputChip(
              label: Text(prayerCountryLabel(context, country)),
              onDeleted: () => setState(() {
                _country = null;
                _search();
              }),
              deleteButtonTooltipMessage: context.prayerLabel('جميع الدول'),
            ),
          ),
        ),
      Expanded(
        child: _loading
            ? Center(child: CircularProgressIndicator())
            : _catalog == null
            ? Center(
                child: TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.prayerLabel('إعادة تحميل المدن')),
                ),
              )
            : _results.cities.isEmpty && _results.countries.isEmpty
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    context.prayerLabel(
                      'لا توجد نتائج. جرّب اسمًا آخر أو حدّد موقعك على الخريطة.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                children: [
                  if (_query.text.trim().isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _country == null
                            ? context.prayerLabel(
                                'ابحث باسم بلدك أو اختر مدينة',
                              )
                            : context.tr(
                                'prayer.cityIn',
                                args: {
                                  'country': prayerCountryLabel(
                                    context,
                                    _country!,
                                  ),
                                },
                              ),
                        style: TextStyle(color: p.muted),
                      ),
                    ),
                  for (final country in _results.countries)
                    ListTile(
                      leading: Icon(Icons.public, color: p.gold),
                      title: Text(prayerCountryLabel(context, country)),
                      subtitle: Text(context.prayerLabel('دولة • عرض المدن')),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => setState(() {
                        _country = country;
                        _query.clear();
                        _search();
                      }),
                    ),
                  for (final city in _results.cities)
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      selected:
                          _selected?.latitude == city.latitude &&
                          _selected?.longitude == city.longitude,
                      selectedTileColor: p.paleTeal,
                      leading: Icon(
                        Icons.location_city_outlined,
                        color: p.tealHeading,
                      ),
                      title: Text(prayerCityLabel(context, city)),
                      subtitle: Text(prayerCountryLabel(context, city.country)),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => _city(city),
                    ),
                ],
              ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          context.prayerLabel(
            'البحث محفوظ دون إنترنت • إن لم تجد بلدتك اختر الخريطة',
          ),
          style: TextStyle(fontSize: 11, color: p.muted),
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );

  Widget _mapView(AppPalette p) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          context.prayerLabel(
            'حرّك الخريطة وكبّرها، ثم اضغط لوضع الدبوس. عرض الخريطة يحتاج إنترنت ويُرسل منطقة العرض لمزوّدها.',
          ),
          style: TextStyle(fontSize: 12, color: p.muted),
          textAlign: TextAlign.center,
        ),
      ),
      if (_tileError)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            context.prayerLabel(
              'تعذّر تحميل بعض أجزاء الخريطة. تحقق من الإنترنت أو استخدم البحث.',
            ),
            style: TextStyle(color: p.heading, fontSize: 12),
          ),
        ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: _pin ?? const LatLng(20, 0),
                  initialZoom: _pin == null ? 2 : 11,
                  minZoom: 2,
                  maxZoom: 18,
                  backgroundColor: p.neutral,
                  onMapReady: () => _mapReady = true,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onTap: (_, point) => _point(point),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.haqfoundation.haq_app',
                    tileProvider: _tiles ??= NetworkTileProvider(
                      headers: {
                        'User-Agent': 'HaqApp/1.0 (com.haqfoundation.haq_app)',
                      },
                      cachingProvider:
                          BuiltInMapCachingProvider.getOrCreateInstance(
                            maxCacheSize: 80 * 1024 * 1024,
                          ),
                    ),
                    maxNativeZoom: 19,
                    panBuffer: 0,
                    errorTileCallback: (_, _, _) {
                      if (!_tileError && mounted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _tileError = true);
                        });
                      }
                    },
                  ),
                  if (_pin case final pin?)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: pin,
                          width: 52,
                          height: 58,
                          alignment: Alignment.topCenter,
                          child: Icon(
                            Icons.location_pin,
                            color: p.tealHeading,
                            size: 52,
                            shadows: [Shadow(color: p.surface, blurRadius: 5)],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              Positioned(
                left: 12,
                top: 12,
                child: Column(
                  children: [
                    _zoom(
                      p,
                      Icons.add,
                      context.prayerLabel('تكبير الخريطة'),
                      1,
                    ),
                    const SizedBox(height: 6),
                    _zoom(
                      p,
                      Icons.remove,
                      context.prayerLabel('تصغير الخريطة'),
                      -1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      InkWell(
        onTap: () => launchUrl(
          Uri.parse('https://www.openstreetmap.org/copyright'),
          mode: LaunchMode.externalApplication,
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            '© OpenStreetMap contributors',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 11,
              color: p.tealHeading,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _zoom(AppPalette p, IconData icon, String label, double delta) =>
      Material(
        color: p.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(14),
        child: IconButton(
          tooltip: label,
          icon: Icon(icon, color: p.heading),
          onPressed: () {
            if (_mapReady) {
              _map.move(
                _map.camera.center,
                (_map.camera.zoom + delta).clamp(2, 18),
              );
            }
          },
        ),
      );

  Widget _selection(AppPalette p) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
    decoration: BoxDecoration(
      color: p.surface,
      border: Border(top: BorderSide(color: p.border)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_resolving) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          Text(context.prayerLabel('جارٍ تحديد المنطقة الزمنية…')),
        ] else if (_selected case final place?) ...[
          Text(
            place.label,
            style: TextStyle(color: p.heading, fontWeight: FontWeight.bold),
          ),
          Text(
            '${place.latitude.toStringAsFixed(5)}, ${place.longitude.toStringAsFixed(5)} · ${place.zone}',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 11, color: p.muted),
          ),
        ] else
          Text(context.prayerLabel('اختر مدينة أو ضع دبوسًا على الخريطة')),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              error,
              style: TextStyle(color: p.heading, fontSize: 12),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('confirm-prayer-location'),
          onPressed:
              _selected == null ||
                  _resolving ||
                  widget.controller.scope != _owner
              ? null
              : () => Navigator.pop(context, _selected),
          icon: const Icon(Icons.check_circle_outline),
          label: Text(context.prayerLabel('اعتماد هذا الموقع')),
        ),
        TextButton(
          onPressed: _credits,
          child: Text(
            context.prayerLabel('مصادر بيانات المواقع والخريطة'),
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );

  Future<void> _credits() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        _creditsContext = context;
        return AlertDialog(
          title: Text(context.prayerLabel('مصادر المواقع')),
          content: SingleChildScrollView(
            child: Text(context.tr('prayer.placeCredits')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.prayerLabel('إغلاق')),
            ),
          ],
        );
      },
    );
    _creditsContext = null;
  }
}
