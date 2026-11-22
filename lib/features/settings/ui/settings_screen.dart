import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/app_info.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/core/theme/theme_providers.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/browse/ui/format.dart' show formatBytes;
import 'package:watchdog/features/index/index_providers.dart';
import 'package:watchdog/features/player/player_providers.dart';
import 'package:watchdog/features/settings/settings_target.dart';
import 'package:watchdog/features/settings/storage_providers.dart';
import 'package:watchdog/features/settings/tmdb_ui_providers.dart';
import 'package:watchdog/features/update/update_providers.dart';
import 'package:watchdog/tmdb/tmdb_client.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_sync.dart';

import 'about_page.dart';
import 'appearance_page.dart';
import 'library_page.dart';
import 'playback_page.dart';
import 'settings_widgets.dart';
import 'tmdb_page.dart';
import 'updates_page.dart';

/// Settings home: a short list of groups, each with a live summary. Tapping
/// one pushes its page.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeTarget());
  }

  /// Open the page a deep link asked for (once), after the current frame so
  /// a route being popped by the caller is out of the way.
  void _consumeTarget() {
    if (!mounted) return;
    final page = ref.read(settingsTargetProvider);
    if (page == null) return;
    ref.read(settingsTargetProvider.notifier).clear();
    _open(page);
  }

  void _open(SettingsPage page) {
    final Widget w = switch (page) {
      SettingsPage.appearance => const AppearancePage(),
      SettingsPage.playback => const PlaybackPage(),
      SettingsPage.library => const LibraryPage(),
      SettingsPage.tmdb => const TmdbPage(),
      SettingsPage.updates => const UpdatesPage(),
      SettingsPage.about => const AboutPage(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsTargetProvider, (_, next) {
      if (next != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _consumeTarget());
      }
    });
    return SettingsPageScaffold(
      title: 'Settings',
      children: [
        _tile(
          const Key('settings-appearance'),
          Icons.palette_outlined,
          'Appearance',
          _appearanceSummary(),
          SettingsPage.appearance,
        ),
        _tile(
          const Key('settings-playback'),
          Icons.play_circle_outline,
          'Playback',
          _playbackSummary(),
          SettingsPage.playback,
        ),
        _tile(
          const Key('settings-library'),
          Icons.video_library_outlined,
          'Library',
          _librarySummary(),
          SettingsPage.library,
        ),
        _tile(
          const Key('settings-tmdb'),
          Icons.movie_filter_outlined,
          'TMDB',
          _tmdbSummary(),
          SettingsPage.tmdb,
        ),
        _tile(
          const Key('settings-updates'),
          Icons.system_update_alt,
          'Updates',
          _updatesSummary(),
          SettingsPage.updates,
        ),
        _tile(
          const Key('settings-about'),
          Icons.info_outline,
          'About',
          'mhm · Apache-2.0',
          SettingsPage.about,
        ),
      ],
    );
  }

  Widget _tile(
    Key key,
    IconData icon,
    String title,
    String summary,
    SettingsPage page,
  ) => SettingsGroupTile(
    key: key,
    icon: icon,
    title: title,
    summary: summary,
    onTap: () => _open(page),
  );

  String _appearanceSummary() {
    final s = ref.watch(themeSettingsProvider);
    final palette = s.followSystem
        ? ref.watch(autoThemeProvider).label
        : s.palette.name;
    return '$palette · ${s.shape == ShapeMode.box ? 'Box' : 'Rounded'}';
  }

  String _playbackSummary() {
    final ask = ref.watch(themeSettingsProvider).askExternalPlayer;
    final audio = ref.watch(preferredAudioProvider);
    return '${ask ? 'Ask every time' : 'Last used player'} · '
        '${audio == null ? 'any audio' : preferredAudioLabel(audio)}';
  }

  String _librarySummary() {
    if (ref.watch(indexStateProvider).value?.running ?? false) {
      return 'Indexing…';
    }
    final counts = ref.watch(countsProvider).value;
    if (counts == null || counts.titles == 0) return 'Not indexed';
    final total = ref.watch(storageUsageProvider).value?.totalBytes;
    // File counts are not shown: a skeleton index only knows them for movies
    // until a series is opened.
    return '${counts.titles} titles'
        '${total == null ? '' : ' · ${formatBytes(total)}'}';
  }

  String _tmdbSummary() {
    final cfg = ref.watch(tmdbConfigProvider).value;
    if (cfg?.auth == null) return 'No key';
    final prog = ref.watch(tmdbProgressProvider).value;
    final state = prog?.state ?? TmdbSyncState.idle;
    if (state == TmdbSyncState.error) {
      return prog?.error == TmdbErrorKind.unauthorized
          ? 'Check your key'
          : 'Sync problem';
    }
    if (state == TmdbSyncState.running) return 'Syncing…';
    final lib = ref.watch(tmdbLibraryProgressProvider).value;
    if (lib == null || lib.eligible == 0) return 'Key saved';
    final done = '${lib.matched} of ${lib.eligible} matched';
    return state == TmdbSyncState.paused ? 'Paused · $done' : done;
  }

  String _updatesSummary() {
    final auto = ref.watch(updatePrefsProvider).value?.autoCheck ?? true;
    return 'v$appVersion · check on launch ${auto ? 'on' : 'off'}';
  }
}
