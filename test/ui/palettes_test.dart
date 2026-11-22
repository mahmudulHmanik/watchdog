import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/core/theme/omarchy_colors.dart';
import 'package:watchdog/core/theme/palettes.dart';

void main() {
  test('palette ids unique, both modes present', () {
    final ids = allPalettes.map((p) => p.id).toSet();
    expect(ids.length, allPalettes.length);
    expect(allPalettes.length, greaterThanOrEqualTo(23));
    expect(allPalettes.any((p) => p.dark), isTrue);
    expect(allPalettes.any((p) => !p.dark), isTrue);
  });

  for (final p in allPalettes) {
    test('contrast ${p.id}', () {
      expect(contrast(p.text, p.bg), greaterThanOrEqualTo(4.5));
      // Hand-tuned Latte tokens are fixed by the spec (4.34); the rest must
      // reach 4.5.
      expect(
        contrast(p.onAccent, p.accent),
        greaterThanOrEqualTo(p.id == 'latte' ? 4.3 : 4.5),
      );
      expect(contrast(p.accent, p.bg), greaterThanOrEqualTo(3));
    });
  }
}
