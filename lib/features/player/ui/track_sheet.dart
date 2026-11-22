import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/features/player/domain/subtitle_style.dart';
import 'package:watchdog/features/player/domain/track_prefs.dart';
import 'package:watchdog/features/player/player_session.dart';

/// Audio / subtitle / video track picker, launched from the player. Sheet
/// shape (Box top border / Rounded radius + handle) comes from the global
/// bottomSheetTheme; the player route adds no theme of its own.
Future<void> showTrackSheet(BuildContext context, PlayerSession session) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ConnectedTrackSheet(session),
    );

class _ConnectedTrackSheet extends StatelessWidget {
  const _ConnectedTrackSheet(this.session);
  final PlayerSession session;

  @override
  Widget build(BuildContext context) {
    final player = session.player;
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, tr) => StreamBuilder<Track>(
        stream: player.stream.track,
        initialData: player.state.track,
        builder: (context, cur) => TrackSheetView(
          tracks: tr.data!,
          selected: cur.data!,
          onAudio: session.selectAudio,
          onSubtitle: session.selectSubtitle,
          onVideo: session.selectVideo,
          onLoadFile: () async {
            final nav = Navigator.of(context);
            final msg = ScaffoldMessenger.of(context);
            try {
              final f = await FilePicker.pickFile(
                dialogTitle: 'Subtitle file',
                type: FileType.custom,
                allowedExtensions: const ['srt', 'ass', 'vtt'],
              );
              final path = f?.path;
              if (path == null) return;
              await session.loadExternalSubtitle(path);
              nav.pop();
            } catch (e) {
              msg.showSnackBar(
                SnackBar(content: Text('Could not load subtitle: $e')),
              );
            }
          },
          onLoadUrl: session.loadExternalSubtitle,
          onStyle: () => showSubtitleStyleSheet(context, session),
        ),
      ),
    );
  }
}

bool _real(String id) => id != 'auto' && id != 'no';

/// The sheet body; pure widget over track data so it can be tested with fake
/// Track lists.
class TrackSheetView extends StatelessWidget {
  const TrackSheetView({
    super.key,
    required this.tracks,
    required this.selected,
    required this.onAudio,
    required this.onSubtitle,
    required this.onVideo,
    required this.onLoadFile,
    required this.onLoadUrl,
    required this.onStyle,
  });
  final Tracks tracks;
  final Track selected;
  final void Function(AudioTrack) onAudio;
  final void Function(SubtitleTrack) onSubtitle;
  final void Function(VideoTrack) onVideo;
  final VoidCallback onLoadFile;
  final Future<void> Function(String) onLoadUrl;
  final VoidCallback onStyle;

  @override
  Widget build(BuildContext context) {
    final audio = tracks.audio.where((t) => _real(t.id)).toList();
    final subs = tracks.subtitle.where((t) => _real(t.id)).toList();
    final video = tracks.video.where((t) => _real(t.id)).toList();
    final aSel = effectiveTrackId(
      [for (final t in audio) (t.id, t.isDefault)],
      selected.audio.id,
      autoPicksFirst: true,
    );
    final sSel = effectiveTrackId(
      [for (final t in subs) (t.id, t.isDefault)],
      selected.subtitle.id,
      autoPicksFirst: false,
    );
    final vSel = effectiveTrackId(
      [for (final t in video) (t.id, t.isDefault)],
      selected.video.id,
      autoPicksFirst: true,
    );
    final aNames = trackNames([for (final t in audio) (t.language, t.title)]);
    final sNames = trackNames([for (final t in subs) (t.language, t.title)]);
    final vNames = trackNames([for (final t in video) (t.language, t.title)]);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const _Group('Audio'),
        if (audio.isEmpty)
          const TrackRow(name: 'No audio tracks', selected: false),
        for (var i = 0; i < audio.length; i++)
          TrackRow(
            name: aNames[i],
            meta: trackMeta(
              codec: audio[i].codec,
              channels: audio[i].channels,
              channelCount: audio[i].audiochannels ?? audio[i].channelscount,
            ),
            selected: audio[i].id == aSel,
            onTap: () => onAudio(audio[i]),
          ),
        const _Group('Subtitles'),
        TrackRow(
          name: 'Off',
          selected: sSel == null,
          onTap: () => onSubtitle(SubtitleTrack.no()),
        ),
        for (var i = 0; i < subs.length; i++)
          TrackRow(
            name: sNames[i],
            meta: trackMeta(codec: subs[i].codec),
            selected: subs[i].id == sSel,
            onTap: () => onSubtitle(subs[i]),
          ),
        if (video.length > 1) ...[
          const _Group('Video'),
          for (var i = 0; i < video.length; i++)
            TrackRow(
              name: vNames[i],
              meta: trackMeta(
                codec: video[i].codec,
                w: video[i].w,
                h: video[i].h,
              ),
              selected: video[i].id == vSel,
              onTap: () => onVideo(video[i]),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _SheetButton(
                  label: 'Load .srt file',
                  onPressed: onLoadFile,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SheetButton(
                  label: 'Subtitle style',
                  onPressed: onStyle,
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextButton(
              onPressed: () => _urlDialog(context),
              child: const Text('From URL...'),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _urlDialog(BuildContext context) async {
    final ctl = TextEditingController();
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Subtitle from URL or path'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'http://... or /path/file.srt',
              errorText: err,
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste),
                onPressed: () async {
                  final d = await Clipboard.getData(Clipboard.kTextPlain);
                  if (d?.text != null) ctl.text = d!.text!.trim();
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await onLoadUrl(ctl.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  set(() => err = '$e');
                }
              },
              child: const Text('Load'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 12 * 0.06,
        color: context.tokens.palette.muted,
      ),
    ),
  );
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: context.tokens.border),
        shape: RoundedRectangleBorder(borderRadius: context.tokens.radius()),
      ),
      child: Text(label),
    ),
  );
}

/// 48 px picker row: radio, name, right-aligned muted meta.
class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.name,
    required this.selected,
    this.meta,
    this.onTap,
  });
  final String name;
  final String? meta;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = t.palette;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? t.hi : null,
          border: selected && t.box
              ? Border(left: BorderSide(color: t.accent, width: 3))
              : null,
        ),
        child: Row(
          children: [
            _Radio(
              selected: selected,
              box: t.box,
              accent: t.accent,
              border: p.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: selected ? t.accent : p.text,
                ),
              ),
            ),
            if (meta != null && meta!.isNotEmpty)
              Text(meta!, style: TextStyle(fontSize: 12, color: p.muted)),
          ],
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({
    required this.selected,
    required this.box,
    required this.accent,
    required this.border,
  });
  final bool selected, box;
  final Color accent, border;
  @override
  Widget build(BuildContext context) {
    final c = selected ? accent : border;
    return Container(
      key: ValueKey(selected ? 'radio-on' : 'radio-off'),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: box ? BoxShape.rectangle : BoxShape.circle,
        border: Border.all(color: c, width: 2),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accent,
                shape: box ? BoxShape.rectangle : BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

/// Second sheet: size, position, colour, background box; applied live.
Future<void> showSubtitleStyleSheet(
  BuildContext context,
  PlayerSession session,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  builder: (_) => SubtitleStyleView(
    initial: session.subStyle.value,
    onChanged: session.setSubtitleStyle,
  ),
);

class SubtitleStyleView extends StatefulWidget {
  const SubtitleStyleView({
    super.key,
    required this.initial,
    required this.onChanged,
  });
  final SubtitleStyle initial;
  final void Function(SubtitleStyle) onChanged;

  @override
  State<SubtitleStyleView> createState() => _SubtitleStyleViewState();
}

class _SubtitleStyleViewState extends State<SubtitleStyleView> {
  late SubtitleStyle _s = widget.initial;

  void _set(SubtitleStyle s) {
    setState(() => _s = s);
    widget.onChanged(s);
  }

  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    children: [
      const _Group('Size'),
      Wrap(
        spacing: 8,
        children: [
          for (final v in SubtitleStyle.scales)
            ChoiceChip(
              label: Text('${(v * 100).round()}%'),
              selected: _s.scale == v,
              onSelected: (_) => _set(_s.copyWith(scale: v)),
            ),
        ],
      ),
      const _Group('Position'),
      Slider(
        value: _s.pos.toDouble(),
        min: 0,
        max: 100,
        divisions: 20,
        label: '${_s.pos}',
        onChanged: (v) => _set(_s.copyWith(pos: v.round())),
      ),
      const _Group('Text colour'),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('White'),
            selected: !_s.yellow,
            onSelected: (_) => _set(_s.copyWith(yellow: false)),
          ),
          ChoiceChip(
            label: const Text('Yellow'),
            selected: _s.yellow,
            onSelected: (_) => _set(_s.copyWith(yellow: true)),
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Background box'),
        value: _s.box,
        onChanged: (v) => _set(_s.copyWith(box: v)),
      ),
    ],
  );
}
