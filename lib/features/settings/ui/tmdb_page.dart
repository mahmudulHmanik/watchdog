import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/models.dart' show TmdbProgress;
import 'package:watchdog/data/repository.dart';
import 'package:watchdog/features/browse/browse_providers.dart';
import 'package:watchdog/features/search/search_providers.dart'
    show tmdbHasDataProvider;
import 'package:watchdog/features/settings/tmdb_ui_providers.dart';
import 'package:watchdog/features/settings/ui/settings_widgets.dart';
import 'package:watchdog/features/title/tmdb_title_providers.dart';
import 'package:watchdog/features/title/ui/file_actions_sheet.dart'
    show showToast;
import 'package:watchdog/platform/platform_api.dart';
import 'package:watchdog/tmdb/tmdb_client.dart';
import 'package:watchdog/tmdb/tmdb_providers.dart';
import 'package:watchdog/tmdb/tmdb_sync.dart';

/// Settings -> TMDB page: key, fetching, data. Short blocks, same behaviour
/// as the old single section.
class TmdbPage extends ConsumerStatefulWidget {
  const TmdbPage({super.key});

  @override
  ConsumerState<TmdbPage> createState() => _TmdbPageState();
}

class _TmdbPageState extends ConsumerState<TmdbPage> {
  @override
  void initState() {
    super.initState();
    // Counts are throttled while a sync runs; read them fresh on open.
    Future.microtask(() {
      if (mounted) ref.invalidate(tmdbLibraryProgressProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(tmdbConfigProvider).value;
    final hasKey = cfg?.auth != null;
    final lib = ref.watch(tmdbLibraryProgressProvider).value;
    final hasData = lib != null && (lib.matched + lib.unmatched) > 0;
    return SettingsPageScaffold(
      title: 'TMDB',
      children: [
        const _KeyBlock(),
        const _HelpBlock(),
        if (hasKey && cfg?.settings != null) const _FetchingBlock(),
        if (hasKey || hasData) const _DataBlock(),
      ],
    );
  }
}

Widget _note(BuildContext context, String text, {Color? color, Key? key}) =>
    Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        key: key,
        style: TextStyle(
          fontSize: 13,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );

/// Key field, save / test / clear.
class _KeyBlock extends ConsumerStatefulWidget {
  const _KeyBlock();

  @override
  ConsumerState<_KeyBlock> createState() => _KeyBlockState();
}

class _KeyBlockState extends ConsumerState<_KeyBlock> {
  final _ctl = TextEditingController();
  String? _keyError;
  ({bool ok, String text})? _test;
  bool _testing = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final text = d?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() {
        _ctl.text = text;
        _keyError = null;
      });
    }
  }

  Future<void> _save() async {
    final r = await ref
        .read(tmdbConfigProvider.notifier)
        .saveCredential(_ctl.text);
    if (!mounted) return;
    setState(() {
      _test = null;
      switch (r) {
        case TmdbSaveResult.saved:
          _ctl.clear();
          _keyError = null;
        case TmdbSaveResult.invalid:
          _keyError =
              'Not a TMDB key. Use the API Key (32 characters) or the API '
              'Read Access Token (starts with eyJ).';
        case TmdbSaveResult.storageFailed:
          _keyError = 'Could not store the key on this device';
      }
    });
  }

  Future<void> _runTest() async {
    final client = ref.read(tmdbClientProvider);
    if (client == null) return;
    setState(() {
      _testing = true;
      _test = null;
    });
    String text;
    var ok = false;
    try {
      await client.validate();
      ok = true;
      text = 'Key works.';
    } on TmdbException catch (e) {
      text = tmdbErrorText(e);
    } catch (e) {
      text = tmdbErrorText(e);
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _test = (ok: ok, text: text);
    });
  }

  Future<void> _clearKey() async {
    final ok = await ref.read(tmdbConfigProvider.notifier).clearCredential();
    if (!mounted) return;
    setState(
      () => _test = ok
          ? null
          : (ok: false, text: 'Could not remove the key from this device'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final hasKey = ref.watch(tmdbConfigProvider).value?.auth != null;
    return SettingsBlock(
      title: 'KEY',
      children: [
        Padding(
          padding: settingsPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasKey
                        ? Icons.check_circle_outline
                        : Icons.key_off_outlined,
                    size: 18,
                    color: hasKey ? t.palette.ok : muted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hasKey ? 'Key saved' : 'No key saved',
                    key: const Key('tmdb-key-status'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('tmdb-key-field'),
                controller: _ctl,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                onSubmitted: (_) => _save(),
                onChanged: (_) {
                  if (_keyError != null) setState(() => _keyError = null);
                },
                decoration: InputDecoration(
                  labelText: hasKey
                      ? 'Replace key'
                      : 'API key or read access token',
                  errorText: _keyError,
                  errorMaxLines: 3,
                  suffixIcon: IconButton(
                    key: const Key('tmdb-paste'),
                    tooltip: 'Paste',
                    icon: const Icon(Icons.content_paste),
                    onPressed: _paste,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const Key('tmdb-save'),
                    onPressed: _save,
                    child: const Text('Save key'),
                  ),
                  OutlinedButton(
                    key: const Key('tmdb-test'),
                    onPressed: hasKey && !_testing ? _runTest : null,
                    child: Text(_testing ? 'Testing...' : 'Test key'),
                  ),
                  if (hasKey)
                    OutlinedButton(
                      key: const Key('tmdb-clear-key'),
                      onPressed: _clearKey,
                      child: const Text('Clear key'),
                    ),
                ],
              ),
              if (_test != null)
                _note(
                  context,
                  _test!.text,
                  key: const Key('tmdb-test-result'),
                  color: _test!.ok ? t.palette.ok : t.palette.error,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// How to get a free key, with copy-link.
class _HelpBlock extends ConsumerWidget {
  const _HelpBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsBlock(
    title: 'GET A FREE KEY',
    children: [
      Padding(
        padding: settingsPad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create a TMDB account, open Settings > API, request a '
              'Developer key, then paste the API Key or the API Read Access '
              'Token above. It stays on this device.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('tmdb-copy-url'),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy link: themoviedb.org/settings/api'),
              onPressed: () async {
                await ref.read(platformApiProvider).copyUrl(tmdbApiSettingsUrl);
                if (context.mounted) showToast(context, 'Link copied');
              },
            ),
          ],
        ),
      ),
    ],
  );
}

/// Background fetch, language, sync status and controls (key required).
class _FetchingBlock extends ConsumerWidget {
  const _FetchingBlock();

  Future<void> _setBackground(WidgetRef ref, bool v) async {
    await ref.read(tmdbConfigProvider.notifier).setBackgroundFetch(v);
    if (!v) await ref.read(tmdbSyncProvider)?.cancel();
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    String cur,
  ) async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'TMDB language',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            for (final (tag, label) in tmdbLanguageChoices)
              ListTile(
                key: Key('tmdb-lang-$tag'),
                title: Text(label),
                trailing: Text(tag),
                selected: cur == tag,
                onTap: () => Navigator.pop(ctx, tag),
              ),
          ],
        ),
      ),
    );
    if (pick != null && pick != cur) {
      await ref.read(tmdbConfigProvider.notifier).setLanguage(pick);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(tmdbConfigProvider).value?.settings;
    if (settings == null) return const SizedBox();
    final lib = ref.watch(tmdbLibraryProgressProvider).value;
    final prog = ref.watch(tmdbProgressProvider).value;
    return SettingsBlock(
      title: 'FETCHING',
      children: [
        SwitchListTile(
          key: const Key('tmdb-bg'),
          title: const Text('Fetch in background'),
          subtitle: const Text('Fills details for the whole library'),
          value: settings.backgroundFetch,
          onChanged: (v) => _setBackground(ref, v),
        ),
        ListTile(
          key: const Key('tmdb-language'),
          title: const Text('Language'),
          subtitle: const Text(
            'Applies to titles fetched from now on. Clear TMDB data to '
            'refetch in the new language.',
            key: Key('tmdb-language-note'),
          ),
          trailing: Text(tmdbLanguageLabel(settings.language)),
          onTap: () => _pickLanguage(context, ref, settings.language),
        ),
        Padding(
          padding: settingsPad,
          child: _SyncStatus(lib: lib, prog: prog),
        ),
      ],
    );
  }
}

/// Clear all downloaded TMDB data (asks first).
class _DataBlock extends ConsumerWidget {
  const _DataBlock();

  Future<void> _clearData(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear TMDB data?'),
        content: const Text(
          'Removes all downloaded TMDB details (ratings, genres, cast, '
          'matches, manual fixes). Your index and watch history stay. '
          'Details are fetched again when you open a title or run the sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('tmdb-clear-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(tmdbSyncProvider)?.cancel();
    await ref.read(repositoryProvider).clearTmdb();
    ref.invalidate(tmdbLibraryProgressProvider);
    ref.invalidate(tmdbHasDataProvider);
    ref.invalidate(tmdbInfoProvider);
    ref.read(revisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final err = context.tokens.palette.error;
    return SettingsBlock(
      title: 'DATA',
      children: [
        Padding(
          padding: settingsPad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Removes downloaded TMDB details and matches. Your index and '
                'watch history stay.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const Key('tmdb-clear-data'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: err,
                  side: BorderSide(color: err),
                ),
                onPressed: () => _clearData(context, ref),
                child: const Text('Clear TMDB data'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SyncStatus extends ConsumerWidget {
  const _SyncStatus({required this.lib, required this.prog});
  final TmdbProgress? lib;
  final TmdbSyncProgress? prog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final sync = ref.read(tmdbSyncProvider);
    final state = prog?.state ?? TmdbSyncState.idle;
    final (label, action) = switch (state) {
      TmdbSyncState.running => ('Pause', sync?.pause),
      TmdbSyncState.paused => ('Resume', sync?.resume),
      _ => ('Start', sync?.start),
    };
    final unauthorized =
        state == TmdbSyncState.error &&
        prog?.error == TmdbErrorKind.unauthorized;
    final msg = prog?.message;
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lib == null
                ? 'Sync status'
                : 'Matched ${lib!.matched} · Unmatched ${lib!.unmatched} · '
                      'Pending ${lib!.pending < 0 ? 0 : lib!.pending}',
            key: const Key('tmdb-counts'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (state == TmdbSyncState.running && prog?.current != null)
            Text(
              'Looking up: ${prog!.current}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: muted),
            ),
          if (state == TmdbSyncState.paused)
            Text('Paused', style: TextStyle(fontSize: 13, color: muted)),
          if (state == TmdbSyncState.error && msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                unauthorized
                    ? 'TMDB rejected the key. Check your key (Test key above).'
                    : tmdbErrorText(
                        TmdbException(
                          prog?.error ?? TmdbErrorKind.badResponse,
                          msg,
                        ),
                      ),
                key: const Key('tmdb-sync-error'),
                style: TextStyle(fontSize: 13, color: t.palette.error),
              ),
            )
          else if (msg != null)
            Text(
              tmdbErrorText(TmdbException(TmdbErrorKind.badResponse, msg)),
              style: TextStyle(fontSize: 13, color: muted),
            ),
          if ((prog?.failed ?? 0) > 0)
            Text(
              '${prog!.failed} failed, will retry next run',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('tmdb-sync-toggle'),
            icon: Icon(
              state == TmdbSyncState.running ? Icons.pause : Icons.play_arrow,
            ),
            label: Text(state == TmdbSyncState.error ? 'Retry' : label),
            onPressed: action,
          ),
        ],
      ),
    );
  }
}
