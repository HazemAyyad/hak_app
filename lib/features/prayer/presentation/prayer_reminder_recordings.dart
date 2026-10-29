part of 'prayer_page.dart';

/// Human recordings only. No generated speech or audio extracted from apps.
class PrayerReminderRecordingsPage extends StatefulWidget {
  const PrayerReminderRecordingsPage({super.key, required this.controller});
  final PrayerController controller;
  @override
  State<PrayerReminderRecordingsPage> createState() =>
      _PrayerReminderRecordingsPageState();
}

class _PrayerReminderRecordingsPageState
    extends State<PrayerReminderRecordingsPage> {
  Set<String> available = {};
  PrayerName? busy;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    unawaited(_refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final status = await AdhanLibrary.bridge.invokeMapMethod<String, dynamic>(
        'adhanStatus',
      );
      if (mounted) {
        setState(
          () => available = Set<String>.from(
            status?['reminderRecordings'] as List? ?? [],
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _import(PrayerName prayer) async {
    if (busy != null) return;
    final owner = widget.controller.scope;
    setState(() {
      busy = prayer;
      error = null;
    });
    File? temporary;
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'تسجيل بشري MP3',
            extensions: ['mp3'],
            mimeTypes: ['audio/mpeg'],
          ),
        ],
      );
      if (file == null || !mounted || owner != widget.controller.scope) return;
      final size = await file.length();
      if (size < 1000 || size > 4 * 1024 * 1024) throw const FormatException();
      final bytes = await file.readAsBytes();
      if (!(bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) &&
          !(bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)) {
        throw const FormatException();
      }
      final root = await getApplicationSupportDirectory();
      temporary = File(
        '${root.path}/${prayerReminderVoiceId(owner, prayer)}-import.mp3',
      );
      await temporary.writeAsBytes(bytes, flush: true);
      if (!mounted || owner != widget.controller.scope) return;
      final ok = await AdhanLibrary.bridge.invokeMethod<bool>(
        'preparePrayerReminder',
        {'id': prayerReminderVoiceId(owner, prayer), 'path': temporary.path},
      );
      if (ok != true) throw const FormatException();
      await _refresh();
      if (mounted && owner == widget.controller.scope) {
        await widget.controller.save(widget.controller.config);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'تعذّر إضافة التسجيل. استخدم MP3 صالحًا لا يتجاوز 30 ثانية و4 ميغابايت.',
        );
      }
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppPalette.of(context).background,
      body: ListView(
        children: [
          DirectoryHeader(
            title: 'التذكير بصوت بشري',
            subtitle: 'تسجيل قصير يذكر اسم الصلاة',
            onBack: () => Navigator.maybePop(context),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _notice(
                  context,
                  'أضف تسجيلات بشرية تملك حق استخدامها، مثل «اقتربت صلاة الفجر». لا نستبدلها بنطق آلي. بدون ملف تبقى نغمة التنبيه العادية.',
                ),
                if (error != null) _notice(context, error!),
                for (final prayer in PrayerName.values.where(
                  (p) => p != PrayerName.sunrise,
                ))
                  _panel(
                    context,
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('اقتربت صلاة ${prayer.label}'),
                      subtitle: Text(
                        available.contains(
                              prayerReminderVoiceId(
                                widget.controller.scope,
                                prayer,
                              ),
                            )
                            ? 'التسجيل جاهز على هذا الجهاز'
                            : 'لم يُضف تسجيل بعد',
                      ),
                      trailing: busy == prayer
                          ? const CircularProgressIndicator()
                          : IconButton(
                              tooltip: 'إضافة تسجيل ${prayer.label}',
                              icon: const Icon(Icons.audio_file_outlined),
                              onPressed: busy != null
                                  ? null
                                  : () => _import(prayer),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
