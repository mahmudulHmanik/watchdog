import 'package:material_ui/material_ui.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/features/browse/ui/format.dart';
import 'package:watchdog/features/browse/ui/title_tile.dart';

class TitleHeader extends StatelessWidget {
  const TitleHeader(this.t, {super.key, this.subtitle});
  final MediaTitle t;

  /// e.g. `S02 · E05` for the current/resume episode.
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Poster(t.posterUrl, width: 90, height: 135),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.name,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!),
              Text(titleSubtitle(t)),
              if (t.kind == TitleKind.series && t.fileCount > 0)
                Text('${t.fileCount} episodes'),
              if (t.tags.isNotEmpty) Text(t.tags.join(', ')),
            ],
          ),
        ),
      ],
    ),
  );
}
