import '../../quran/data/haq_api.dart';

part 'adhan_catalog.dart';
part 'nusuk_adhan_catalog.dart';

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
    this.voice = 'nusuk-1',
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
        adhanVoiceById(data['voice'] as String) == null) {
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
  const AdhanVoice(
    this.id,
    this.name,
    this.file, {
    this.source = 'AlAdhan / Islamic Network',
    this.sourceUrl = 'https://aladhan.com/download-adhans',
    this.backend = false,
    this.englishName,
    this.bytes,
    this.sha256,
    this.shortBytes,
    this.shortSha256,
    this.asset,
    this.shortAsset,
  });
  final String id, name, file, source, sourceUrl;
  final bool backend;
  final String? englishName, sha256, shortSha256, asset, shortAsset;
  final int? bytes, shortBytes;
  bool get bundled => asset != null && shortAsset != null;
  bool get hasShort => shortBytes != null && shortSha256 != null;
  int get downloadBytes => (bytes ?? 0) + (shortBytes ?? 0);
  Uri _backendUri(String kind) => Uri.parse(
    '${haqApiBase.replaceAll(RegExp(r'/+$'), '')}/v1/religious/adhans/$id/$kind',
  );
  Uri get uri => backend
      ? _backendUri('full')
      : file.startsWith('https://')
      ? Uri.parse(file)
      : Uri.https('cdn.aladhan.com', '/audio/adhans/$file');
  Uri? get shortUri => hasShort ? _backendUri('takbeer') : null;

  bool sameRecording(AdhanVoice other) =>
      uri == other.uri &&
      shortUri == other.shortUri &&
      bytes == other.bytes &&
      sha256 == other.sha256 &&
      shortBytes == other.shortBytes &&
      shortSha256 == other.shortSha256 &&
      asset == other.asset &&
      shortAsset == other.shortAsset;
}

// Public download catalogue, publisher attribution retained. Never relabel a
// recording as one of the reference app's muezzins without a matching source.
const legacyAdhanVoices = [
  AdhanVoice('alafasy', 'مشاري راشد العفاسي', 'a9.mp3'),
  AdhanVoice('nafees', 'أحمد النفيس', 'a1.mp3'),
  AdhanVoice('mustafa', 'حافظ مصطفى أوزجان', 'a2.mp3'),
  AdhanVoice('zahrani', 'منصور الزهراني', 'a11-mansour-al-zahrani.mp3'),
  ..._additionalAdhanVoices,
];

// Keep historical recording identities readable after replacing the selectable
// catalogue. A new recording must never reuse an older recording's identifier.
const adhanVoices = nusukAdhanVoices;

Iterable<AdhanVoice> get allAdhanVoices sync* {
  final seen = <String>{};
  for (final voice in [...adhanVoices, ...legacyAdhanVoices]) {
    if (seen.add(voice.id)) yield voice;
  }
}

AdhanVoice? adhanVoiceById(String id) =>
    allAdhanVoices.where((voice) => voice.id == id).firstOrNull;
