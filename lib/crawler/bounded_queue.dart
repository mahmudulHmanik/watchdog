// Bounded producer/consumer queue: producers wait for space, so a slow
// consumer (the index writer) throttles the crawl and memory stays flat.
import 'dart:async';
import 'dart:collection';

/// Single consumer, many producers.
///
/// Producers call [reserve] (waits while `length + reserved >= capacity`)
/// then [put], or just `await add(x)`. The consumer reads [stream]; an item
/// leaves the buffer when the stream hands it over, so buffering is at most
/// [capacity] + the one item being processed. Use `await for` (or pause the
/// subscription) so the stream really applies backpressure.
class BoundedQueue<T> {
  BoundedQueue(this.capacity) : assert(capacity > 0);

  final int capacity;
  final _items = Queue<T>();
  final _waiters = Queue<Completer<void>>();
  int _reserved = 0;
  bool _closed = false, _aborted = false, _consumerGone = false;

  /// Called once when the consumer cancels its subscription.
  void Function()? onConsumerCancel;

  int get length => _items.length;
  int get reserved => _reserved;
  bool get consumerGone => _consumerGone;

  /// Claims one slot, waiting for space. Completes immediately after
  /// [abort] or when the consumer is gone.
  Future<void> reserve() {
    if (_aborted || _consumerGone || _items.length + _reserved < capacity) {
      _reserved++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  /// Gives back a slot claimed with [reserve] that was not used.
  void release() {
    if (_reserved > 0) _reserved--;
    _wake();
  }

  /// Adds an item, consuming a reservation if one is held. Dropped after the
  /// consumer cancelled or the queue closed.
  void put(T item) {
    if (_reserved > 0) _reserved--;
    if (_closed || _consumerGone) return;
    _items.add(item);
    _ping();
  }

  Future<void> add(T item) async {
    await reserve();
    put(item);
  }

  /// No more items; the stream ends after the buffer drains.
  void close() {
    _closed = true;
    _ping();
    _wake(all: true);
  }

  /// Stops applying backpressure (cancelled crawl): waiting producers resume.
  void abort() {
    _aborted = true;
    _wake(all: true);
  }

  bool _drainScheduled = false;

  void _ping() {
    if (_drainScheduled) return;
    _drainScheduled = true;
    scheduleMicrotask(() {
      _drainScheduled = false;
      _drain();
    });
  }

  // Sync controller: `await for` pauses the subscription inside add(), so the
  // loop stops after one item per iteration of the consumer.
  late final _ctrl = StreamController<T>(
    sync: true,
    onListen: _ping,
    onResume: _ping,
    onCancel: () {
      if (!_closed || _items.isNotEmpty) {
        _consumerGone = true;
        _items.clear();
        _wake(all: true);
        onConsumerCancel?.call();
      }
    },
  );

  void _drain() {
    while (_ctrl.hasListener && !_ctrl.isPaused && _items.isNotEmpty) {
      final x = _items.removeFirst();
      _wake();
      _ctrl.add(x);
    }
    if (_closed && _items.isEmpty && !_ctrl.isClosed) _ctrl.close();
  }

  void _wake({bool all = false}) {
    while (_waiters.isNotEmpty &&
        (all ||
            _aborted ||
            _consumerGone ||
            _items.length + _reserved < capacity)) {
      _reserved++;
      _waiters.removeFirst().complete();
    }
  }

  /// Single-subscription stream of the queued items.
  Stream<T> get stream => _ctrl.stream;
}
