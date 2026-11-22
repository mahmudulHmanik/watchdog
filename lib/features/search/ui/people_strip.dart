import 'package:watchdog/features/browse/ui/app_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:watchdog/core/theme/app_theme.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/tmdb/tmdb_images.dart';

import 'tmdb_labels.dart';

/// Round (Box: square) actor photo, initials when there is no image.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar(this.person, {super.key, this.size = 40});
  final PersonHit person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: t.hi,
      child: Text(
        initials(person.name),
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
    final url = tmdbImageUrl(person.profilePath, TmdbImageSize.profile);
    return ClipRRect(
      borderRadius: t.radius(size / 2),
      child: url == null
          ? fallback
          : AppImage(
              url,
              width: size,
              height: size,
              cacheWidth: (size * 2).round(),
              fallback: fallback,
            ),
    );
  }
}

/// Compact horizontal strip of actors matching the search text.
class PeopleStrip extends StatelessWidget {
  const PeopleStrip({super.key, required this.people, required this.onPick});
  final List<PersonHit> people;
  final void Function(PersonHit) onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      key: const Key('people-strip'),
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: people.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = people[i];
          return InkWell(
            key: Key('person-${p.id}'),
            borderRadius: t.radius(12),
            onTap: () => onPick(p),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
              decoration: t.plain(r: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PersonAvatar(p, size: 40),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          titleCountLabel(p.titleCount),
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
