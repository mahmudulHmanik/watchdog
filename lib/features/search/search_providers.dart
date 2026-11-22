import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watchdog/data/models.dart';

class SearchFilterNotifier extends Notifier<BrowseFilter> {
  @override
  BrowseFilter build() => const BrowseFilter();
  void set(BrowseFilter f) => state = f;
}

final searchFilterProvider =
    NotifierProvider<SearchFilterNotifier, BrowseFilter>(
      SearchFilterNotifier.new,
    );
