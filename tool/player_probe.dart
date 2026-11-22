// Headless media_kit probe: opens ONE BDIX URL paused with no video output,
// prints duration + audio/subtitle/video tracks, then disposes. Needs system
// libmpv (Linux) and BDIX access. Reads only container metadata (mpv fetches
// headers/index, never the whole file).
//
//   dart run tool/player_probe.dart [url]
import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:watchdog/features/player/domain/mpv_tuning.dart';

const _defaultUrl =
    'http://172.16.50.7/DHAKA-FLIX-7/English%20Movies/%282010%29/'
    'Alice%20in%20Wonderland%20%282010%29%20720p%20%5BDual%20Audio%5D/'
    'Alice%20in%20Wonderland%20%282010%29%20720p%20BluRay%20x264%20ESub'
    '%20%5BDual%20Audio%5D%5BHindi%202.0%2BEnglish%205.1%5D%20-mkvC.mkv';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args.first : _defaultUrl;
  MediaKit.ensureInitialized();
  final player = Player(
    configuration: const PlayerConfiguration(vo: 'null', bufferSize: 8 << 20),
  );
  await applyStreamTuning(player);
  final errors = <String>[];
  final subs = [player.stream.error.listen(errors.add)];
  try {
    await player.setAudioTrack(AudioTrack.auto());
    await player.open(Media(url), play: false);
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline) && errors.isEmpty) {
      final s = player.state;
      if (s.duration > Duration.zero && s.tracks.audio.length > 2) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final s = player.state;
    stdout.writeln('duration: ${s.duration}');
    for (final (name, list) in [
      ('video', s.tracks.video),
      ('audio', s.tracks.audio),
      ('subtitle', s.tracks.subtitle),
    ]) {
      stdout.writeln('$name tracks (${list.length}):');
      for (final t in list) {
        stdout.writeln(
          '  id=${t.id} lang=${t.language} title=${t.title} codec=${t.codec} '
          'ch=${t.channels} ${t.w != null ? "${t.w}x${t.h}" : ""}',
        );
      }
    }
    stdout.writeln('selected: audio=${s.track.audio.id} sub=${s.track.subtitle.id} video=${s.track.video.id}');
    final aid = await (player.platform as NativePlayer).getProperty('aid');
    stdout.writeln('mpv aid=$aid');
    if (errors.isNotEmpty) stdout.writeln('errors: $errors');
    exitCode = (s.duration > Duration.zero && errors.isEmpty) ? 0 : 1;
  } finally {
    for (final x in subs) {
      await x.cancel();
    }
    await player.dispose();
  }
}
