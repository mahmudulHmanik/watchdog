// Adapts the saved crawl (tv.json / all.json) to classifier FolderNodes.
import 'dart:convert';
import 'dart:io';

import 'package:watchdog/core/config/crawl_config.dart';
import 'package:watchdog/crawler/classifier.dart';
import 'package:watchdog/data/models.dart';

DateTime? _d(Object? s) {
  final m = RegExp(r'^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d)$')
      .firstMatch('${s ?? ''}');
  if (m == null) return null;
  return DateTime(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
  );
}

FolderNode nodeFromJson(Map n) {
  final kids = (n['kids'] as List? ?? const []).cast<Map>();
  return FolderNode(
    name: n['name'] as String,
    url: n['href'] as String,
    mtime: _d(n['d']),
    files: [
      for (final k in kids.where((k) => k['t'] != 'folder'))
        NodeFile(
          name: k['name'] as String,
          url: k['href'] as String,
          sizeKb: int.tryParse(
            RegExp(r'^\d+').firstMatch('${k['s']}')?[0] ?? '',
          ),
          mtime: _d(k['d']),
        ),
    ],
    folders: [
      for (final k in kids.where((k) => k['t'] == 'folder')) nodeFromJson(k),
    ],
  );
}

/// Category name -> (layout, kind) for the saved crawl's category keys.
const corpusCategories = <String, (LayoutKind, TitleKind)>{
  'TV-WEB-Series': (LayoutKind.series, TitleKind.series),
  'Korean Series': (LayoutKind.series, TitleKind.series),
  'Anime & Cartoon': (LayoutKind.series, TitleKind.series),
  'WWE & AEW': (LayoutKind.events, TitleKind.event),
  'Awards & TV Shows': (LayoutKind.events, TitleKind.event),
};

/// Loads dir/{tv,all}.json as category name -> synthetic root node.
/// Returns null when the files are absent.
Map<String, FolderNode>? loadCorpus(String dir) {
  final tvF = File('$dir/tv.json'), allF = File('$dir/all.json');
  if (!tvF.existsSync() || !allF.existsSync()) return null;
  final all = jsonDecode(allF.readAsStringSync()) as Map;
  all['TV-WEB-Series'] = jsonDecode(tvF.readAsStringSync());
  return {
    for (final e in all.entries)
      e.key as String: FolderNode(
        name: e.key as String,
        url: '',
        folders: [
          for (final i in (e.value as List).cast<Map>()) nodeFromJson(i),
        ],
      ),
  };
}
