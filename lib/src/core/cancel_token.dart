import 'dart:async';

class CancelledException implements Exception {
  final String? reason;

  const CancelledException([this.reason]);

  @override
  String toString() => reason == null ? 'CancelledException' : 'CancelledException: $reason';
}

typedef CancelListener = void Function(String? reason);

class CancelToken {
  bool _isCancelled = false;
  String? _reason;
  final List<CancelListener> _listeners = <CancelListener>[];

  bool get isCancelled => _isCancelled;
  String? get reason => _reason;

  void cancel([String? reason]) {
    if (_isCancelled) return;
    _isCancelled = true;
    _reason = reason;

    final listeners = List<CancelListener>.from(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      scheduleMicrotask(() => listener(_reason));
    }
  }

  void addListener(CancelListener listener) {
    if (_isCancelled) {
      scheduleMicrotask(() => listener(_reason));
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(CancelListener listener) {
    _listeners.remove(listener);
  }
}
