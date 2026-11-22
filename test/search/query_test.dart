import 'package:flutter_test/flutter_test.dart';
import 'package:watchdog/data/models.dart';
import 'package:watchdog/data/search/query.dart';
import 'package:watchdog/data/search/ranker.dart';

void main() {
  test('normalize', () {
    expect(normalize('Spider-Man: Homecoming'), 'spider man homecoming');
    expect(normalize("Schindler's  List"), 'schindlers list');
    expect(normalize('Amélie'), 'amelie');
    expect(normalize('  A.B_C '), 'a b c');
  });

  test('year hint and range', () {
    final q = ParsedQuery.parse('dune 2021');
    expect(q.tokens, ['dune']);
    expect(q.yearHint, 2021);
    final lone = ParsedQuery.parse('1917');
    expect(lone.tokens, ['1917']);
    expect(lone.yearHint, 1917);
    final r = ParsedQuery.parse('batman 1990-1999');
    expect(r.tokens, ['batman']);
    expect((r.yearMin, r.yearMax), (1990, 1999));
    expect(ParsedQuery.parse('300').tokens, ['300']);
    expect(ParsedQuery.parse('13 hours').tokens, ['13', 'hours']);
  });

  test('season/quality tokens ignored', () {
    var q = ParsedQuery.parse('breaking bad S02');
    expect(q.tokens, ['breaking', 'bad']);
    expect(q.kindHint, TitleKind.series);
    q = ParsedQuery.parse('breaking bad season 2');
    expect(q.tokens, ['breaking', 'bad']);
    expect(q.kindHint, TitleKind.series);
    q = ParsedQuery.parse('the season of witch');
    expect(q.tokens, ['the', 'season', 'of', 'witch']);
    q = ParsedQuery.parse('dune 1080p');
    expect(q.tokens, ['dune']);
    expect(q.qualityHint, 1080);
  });

  test('damerau', () {
    expect(damerau('teh', 'the'), 1);
    expect(damerau('kitten', 'sitting'), 3);
    expect(damerau('abc', 'abc'), 0);
  });
}
