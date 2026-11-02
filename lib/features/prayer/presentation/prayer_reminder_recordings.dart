part of 'prayer_page.dart';

/// Offline reminder choices, with optional recordings supplied by the user.
class PrayerReminderRecordingsPage extends StatefulWidget {
  const PrayerReminderRecordingsPage({
    super.key,
    required this.controller,
    this.beforeAudio,
  });
  final Future<void> Function()? beforeAudio;
  final PrayerController controller;
  @override
  State<PrayerReminderRecordingsPage> createState() =>
      _PrayerReminderRecordingsPageState();
}

class _PrayerReminderRecordingsPageState
    extends State<PrayerReminderRecordingsPage> {
  Set<String> available = {};
  final AdhanPreviewAudio audio = NativeAdhanPreview();
  PrayerName? playing;
  late String owner;
  late String variant;
  int generation = 0;
  PrayerName? busy;
  String? error;
  @override
  void initState() {
    super.initState();
    owner = widget.controller.scope;
    variant = widget.controller.reminderVariant;
    widget.controller.addListener(_changed);
    unawaited(_refresh());
  }

  void _changed() {
    if (owner != widget.controller.scope ||
        variant != widget.controller.reminderVariant) {
      owner = widget.controller.scope;
      variant = widget.controller.reminderVariant;
      generation++;
      playing = null;
      unawaited(audio.stop());
    }
    if (mounted) setState(() {});
  }

  bool saving = false;
  Future<void> _savePreferences(PrayerConfig next) async {
    if (saving || busy != null) return;
    setState(() => saving = true);
    try {
      await widget.controller.save(next);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _label(PrayerName p) =>
      LocalizationScope.maybeOf(context)?.code == 'tr' ||
          (variant.startsWith('pn-') &&
              LocalizationScope.maybeOf(context)?.code == 'en')
      ? context.tr(
          'prayer.approaching',
          args: {'prayer': p.displayLabel(context)},
        )
      : variant == 'en'
      ? 'It is almost time for ${p.name[0].toUpperCase()}${p.name.substring(1)} prayer'
      : 'قرب وقت صلاة ${p.label}';

  Future<void> _preview(PrayerName prayer) async {
    final capturedOwner = owner,
        capturedVariant = variant,
        attempt = ++generation;
    final previewVariant = widget.controller.reminderVariantFor(
      prayer,
      widget.controller.now,
    );
    if (playing == prayer) {
      await audio.stop();
      if (mounted && attempt == generation) setState(() => playing = null);
      return;
    }
    setState(() {
      playing = prayer;
      error = null;
    });
    try {
      await audio.stop();
      await widget.beforeAudio?.call();
      final asset = prayerReminderAsset(previewVariant, prayer);
      final bytes = await rootBundle.load(asset);
      final root = await getApplicationSupportDirectory();
      final file = File(
        '${root.path}/haq-reminder-preview-$previewVariant-${prayer.name}.${asset.split('.').last}',
      );
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      if (!mounted ||
          attempt != generation ||
          capturedOwner != widget.controller.scope ||
          capturedVariant != widget.controller.reminderVariant) {
        return;
      }
      await audio.play(file.uri);
    } catch (_) {
      if (mounted && attempt == generation) {
        setState(
          () => error = context.prayerLabel(
            'تعذّر تشغيل المعاينة على هذا الجهاز',
          ),
        );
      }
    } finally {
      if (mounted && attempt == generation) setState(() => playing = null);
    }
  }

  Future<void> _restore(PrayerName prayer) async {
    final captured = widget.controller.scope;
    try {
      final ok = await AdhanLibrary.bridge.invokeMethod<bool>(
        'removePrayerReminder',
        {'id': prayerReminderVoiceId(captured, prayer, variant: variant)},
      );
      if (!mounted || captured != widget.controller.scope || ok != true) return;
      await _refresh();
      await widget.controller.save(widget.controller.config);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = context.prayerLabel(
            'تعذّرت استعادة الصوت المضمّن؛ أعد المحاولة',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    generation++;
    unawaited(audio.dispose());
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
    final importedVariant = widget.controller.reminderVariant;
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
      if (file == null ||
          !mounted ||
          owner != widget.controller.scope ||
          importedVariant != widget.controller.reminderVariant) {
        return;
      }
      final size = await file.length();
      if (size < 1000 || size > 4 * 1024 * 1024) throw const FormatException();
      final bytes = await file.readAsBytes();
      if (!(bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) &&
          !(bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)) {
        throw const FormatException();
      }
      final root = await getApplicationSupportDirectory();
      temporary = File(
        '${root.path}/${prayerReminderVoiceId(owner, prayer, variant: importedVariant)}-import.mp3',
      );
      await temporary.writeAsBytes(bytes, flush: true);
      if (!mounted ||
          owner != widget.controller.scope ||
          importedVariant != widget.controller.reminderVariant) {
        return;
      }
      final ok = await AdhanLibrary.bridge.invokeMethod<bool>(
        'preparePrayerReminder',
        {
          'id': prayerReminderVoiceId(owner, prayer, variant: importedVariant),
          'path': temporary.path,
        },
      );
      if (ok != true) throw const FormatException();
      await _refresh();
      if (mounted && owner == widget.controller.scope) {
        await widget.controller.save(widget.controller.config);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = context.prayerLabel(
            'تعذّر إضافة التسجيل. استخدم MP3 صالحًا لا يتجاوز 30 ثانية و4 ميغابايت.',
          ),
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
    textDirection:
        LocalizationScope.maybeOf(context)?.language.direction ??
        TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppPalette.of(context).background,
      body: ListView(
        children: [
          DirectoryHeader(
            title: context.prayerLabel('أصوات التذكير قبل الصلاة'),
            subtitle: context.prayerLabel(
              'صوت مضمّن لكل صلاة، أو تسجيلك الخاص',
            ),
            onBack: () => Navigator.maybePop(context),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _notice(
                  context,
                  widget.controller.config.reminderSound ==
                          PrayerReminderSound.defaultVoice
                      ? context.prayerLabel(
                          'الصوت الافتراضي عربي مولّد اصطناعيًا، ومضمّن للعمل دون إنترنت. أضف تسجيلك البشري إذا رغبت؛ له الأولوية على الصوت المضمّن.',
                        )
                      : context.tr('prayer.reminderSound.offlineNotice'),
                ),
                if (error != null) _notice(context, error!),
                if (Platform.isIOS &&
                    widget.controller.config.reminderSound ==
                        PrayerReminderSound.wake)
                  _notice(context, context.tr('prayer.reminderSound.iosShort')),
                _panel(
                  context,
                  Column(
                    children: [
                      DropdownButtonFormField<PrayerReminderSound>(
                        key: ValueKey(
                          'reminder-sound-${widget.controller.config.reminderSound.name}',
                        ),
                        initialValue: widget.controller.config.reminderSound,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: context.tr('prayer.reminderSound.title'),
                        ),
                        items: [
                          for (final sound in PrayerReminderSound.values)
                            DropdownMenuItem(
                              value: sound,
                              child: Text(
                                context.tr(
                                  'prayer.reminderSound.${sound.name}',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: saving || busy != null
                            ? null
                            : (sound) {
                                if (sound != null) {
                                  _savePreferences(
                                    widget.controller.config.copyWith(
                                      reminderSound: sound,
                                    ),
                                  );
                                }
                              },
                      ),
                      if (widget.controller.config.reminderSound ==
                          PrayerReminderSound.defaultVoice) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'reminder-language-${widget.controller.config.reminderLanguage}',
                          ),
                          initialValue:
                              widget.controller.config.reminderLanguage,
                          decoration: InputDecoration(
                            labelText: context.prayerLabel(
                              'لغة التذكير / Reminder language',
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'auto',
                              child: Text(
                                context.prayerLabel('تلقائي حسب لغة التطبيق'),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'ar',
                              child: Text(context.prayerLabel('العربية')),
                            ),
                            DropdownMenuItem(
                              value: 'en',
                              child: Text('English'),
                            ),
                          ],
                          onChanged: saving || busy != null
                              ? null
                              : (v) {
                                  if (v != null) {
                                    _savePreferences(
                                      widget.controller.config.copyWith(
                                        reminderLanguage: v,
                                      ),
                                    );
                                  }
                                },
                        ),
                        if (variant != 'en') ...[
                          const SizedBox(height: 16),
                          DropdownButtonFormField<PrayerReminderDialect>(
                            key: ValueKey(
                              'reminder-dialect-${widget.controller.config.reminderDialect.name}',
                            ),
                            initialValue:
                                widget.controller.config.reminderDialect,
                            decoration: InputDecoration(
                              labelText: context.prayerLabel('اللهجة العربية'),
                            ),
                            items: [
                              for (final d in PrayerReminderDialect.values)
                                DropdownMenuItem(
                                  value: d,
                                  child: Text(d.displayLabel(context)),
                                ),
                            ],
                            onChanged: saving || busy != null
                                ? null
                                : (v) {
                                    if (v != null) {
                                      _savePreferences(
                                        widget.controller.config.copyWith(
                                          reminderDialect: v,
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ] else
                          Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text('English uses one voice.'),
                          ),
                      ],
                    ],
                  ),
                ),
                for (final prayer in PrayerName.values.where(
                  (p) => p != PrayerName.sunrise,
                ))
                  _panel(
                    context,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _label(prayer),
                          textDirection: contentTextDirection(_label(prayer)),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppPalette.of(context).heading,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          available.contains(
                                prayerReminderVoiceId(
                                  widget.controller.scope,
                                  prayer,
                                  variant: variant,
                                ),
                              )
                              ? (variant == 'en'
                                    ? 'Your custom recording is ready'
                                    : context.prayerLabel(
                                        'تسجيلك الخاص جاهز على هذا الجهاز',
                                      ))
                              : variant.startsWith('pn-')
                              ? context.tr('prayer.reminderSound.available')
                              : (variant == 'en'
                                    ? 'Synthetic voice • available offline'
                                    : context.prayerLabel(
                                        'صوت مولّد مضمّن • جاهز دون إنترنت',
                                      )),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: saving || busy != null
                                  ? null
                                  : () => _preview(prayer),
                              icon: Icon(
                                playing == prayer
                                    ? Icons.stop_circle_outlined
                                    : Icons.play_circle_outline,
                              ),
                              label: Text(
                                playing == prayer
                                    ? context.prayerLabel('إيقاف / Stop')
                                    : context.prayerLabel('معاينة / Preview'),
                              ),
                            ),
                            if (available.contains(
                              prayerReminderVoiceId(
                                widget.controller.scope,
                                prayer,
                                variant: variant,
                              ),
                            ))
                              IconButton(
                                tooltip: context.tr(
                                  'prayer.restoreVoice',
                                  args: {
                                    'prayer': prayer.displayLabel(context),
                                  },
                                ),
                                icon: const Icon(Icons.restore),
                                onPressed: () => _restore(prayer),
                              ),
                            busy == prayer
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(),
                                  )
                                : IconButton(
                                    tooltip: context.tr(
                                      'prayer.addRecording',
                                      args: {
                                        'prayer': prayer.displayLabel(context),
                                      },
                                    ),
                                    icon: const Icon(Icons.audio_file_outlined),
                                    onPressed: busy != null || saving
                                        ? null
                                        : () => _import(prayer),
                                  ),
                          ],
                        ),
                      ],
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
