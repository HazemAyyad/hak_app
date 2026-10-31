import '../../../core/localization/interface_messages.dart';
import 'quran_audio_models.dart';
import 'quran_repository.dart';

String audioReciterLabel(QuranAudioTrack track, InterfaceMessages messages) =>
    messages.strings['quran.recitation.${track.recitation}.name'] ??
    track.reciter;

/// Display metadata only. Personal recordings and original track/cache identities
/// remain unchanged, including recordings used by the religious-content player.
String audioTrackLabel(
  QuranAudioTrack track,
  QuranRepository repository,
  InterfaceMessages messages,
) {
  final canonical =
      track.recitation.startsWith('mp3quran:') ||
      track.recitation.startsWith('everyayah:') ||
      track.recitation == 'qurancom:word';
  if (!canonical || track.surah < 1 || track.surah > 114) return track.title;
  final chapter = repository.surah(track.surah);
  final name = messages.strings['quran.surah.${track.surah}'] ?? chapter.name;
  return messages.text(
    track.ayah == null ? 'search.surah' : 'search.verse',
    args: {
      'name': name,
      if (track.ayah != null) 'ayah': messages.formats.integer(track.ayah!),
    },
  );
}
