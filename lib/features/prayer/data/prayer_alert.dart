enum PrayerAlertMode {
  chime('نغمة التنبيه'),
  adhan('صوت الأذان'),
  vibration('اهتزاز فقط'),
  silent('صامت');

  const PrayerAlertMode(this.label);
  final String label;
}

class PrayerAlert {
  const PrayerAlert({
    this.mode = PrayerAlertMode.chime,
    this.voice = 'alafasy',
    this.full = false,
  });
  final PrayerAlertMode mode;
  final String voice;
  final bool full;
  PrayerAlert copyWith({PrayerAlertMode? mode, String? voice, bool? full}) =>
      PrayerAlert(
        mode: mode ?? this.mode,
        voice: voice ?? this.voice,
        full: full ?? this.full,
      );
  Map<String, Object> toJson() => {
    'mode': mode.name,
    'voice': voice,
    'full': full,
  };
  factory PrayerAlert.fromJson(Map data) {
    if (data.keys.any((k) => !{'mode', 'voice', 'full'}.contains(k)) ||
        data['mode'] is! String ||
        data['voice'] is! String ||
        data['full'] is! bool ||
        !adhanVoices.any((v) => v.id == data['voice'])) {
      throw const FormatException('Invalid prayer alert');
    }
    return PrayerAlert(
      mode: PrayerAlertMode.values.byName(data['mode'] as String),
      voice: data['voice'] as String,
      full: data['full'] as bool,
    );
  }
}

class AdhanVoice {
  const AdhanVoice(this.id, this.name, this.file);
  final String id, name, file;
  Uri get uri => Uri.https('cdn.aladhan.com', '/audio/adhans/$file');
}

// Public download catalogue, publisher attribution retained. Never relabel a
// recording as one of the reference app's muezzins without a matching source.
const adhanVoices = [
  AdhanVoice('alafasy', 'مشاري راشد العفاسي', 'a9.mp3'),
  AdhanVoice('nafees', 'أحمد النفيس', 'a1.mp3'),
  AdhanVoice('mustafa', 'حافظ مصطفى أوزجان', 'a2.mp3'),
  AdhanVoice('zahrani', 'منصور الزهراني', 'a11-mansour-al-zahrani.mp3'),
];
