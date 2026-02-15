import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:flutter/services.dart';

import 'package:pauza_screen_time/src/core/cancel_token.dart';

/// Runs selected platform-channel calls on a background isolate.
///
/// This is mainly useful for calls that return large payloads (e.g. lists with
/// icon byte arrays), so that platform message decoding doesn't block the UI
/// isolate.
class BackgroundChannelRunner {
  const BackgroundChannelRunner._();

  static final Queue<_PendingRequest> _queue = Queue<_PendingRequest>();
  static _PendingRequest? _inFlight;
  static _IsolateWorker? _worker;
  static int _nextRequestId = 0;
  static Timer? _idleShutdownTimer;
  static const Duration _idleShutdownDelay = Duration(seconds: 30);

  /// Invokes [method] on [channelName] from a background isolate.
  ///
  /// The returned value must be isolate-sendable (e.g. primitives, lists/maps of
  /// sendable values, and typed data like [Uint8List]).
  static Future<T?> invokeMethod<T>(
    String channelName,
    String method, {
    Map<String, dynamic>? arguments,
    CancelToken? cancelToken,
    Duration? timeout,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      throw CancelledException(cancelToken?.reason);
    }

    final token = ServicesBinding.rootIsolateToken;

    // In tests (or unusual initialization flows) the binding may not be
    // initialized. Fall back to running on the current isolate.
    if (token == null || _usesTestBinaryMessenger()) {
      return _invokeOnCurrentIsolate<T>(
        channelName,
        method,
        arguments: arguments,
        cancelToken: cancelToken,
        timeout: timeout,
      );
    }

    final completer = Completer<T?>();
    final request = _PendingRequest(
      id: _nextRequestId++,
      channelName: channelName,
      method: method,
      arguments: arguments,
      completer: completer,
      cancelToken: cancelToken,
      timeout: timeout,
    );

    _enqueue(request);
    return completer.future;
  }

  static bool _usesTestBinaryMessenger() {
    final messengerType = ServicesBinding
        .instance
        .defaultBinaryMessenger
        .runtimeType
        .toString();
    return messengerType.contains('TestDefaultBinaryMessenger');
  }

  static Future<void> shutdown() async {
    _idleShutdownTimer?.cancel();
    _idleShutdownTimer = null;

    const cancelled = CancelledException('shutdown');

    final pending = List<_PendingRequest>.from(_queue);
    _queue.clear();
    for (final request in pending) {
      request.completeError(cancelled);
    }

    final inFlight = _inFlight;
    _inFlight = null;
    inFlight?.completeError(cancelled);

    await _shutdownWorker();
  }

  static void _enqueue(_PendingRequest request) {
    _idleShutdownTimer?.cancel();
    _idleShutdownTimer = null;

    if (request.cancelToken != null) {
      request.cancelListener = (reason) {
        _handleCancellation(request, reason);
      };
      request.cancelToken!.addListener(request.cancelListener!);
    }

    _queue.add(request);
    _dispatchNext();
  }

  static void _dispatchNext() {
    if (_inFlight != null) return;
    if (_queue.isEmpty) {
      _scheduleIdleShutdown();
      return;
    }

    final request = _queue.removeFirst();
    _inFlight = request;

    _ensureWorker()
        .then((worker) {
          if (_inFlight != request) return;

          if (request.cancelToken?.isCancelled ?? false) {
            _handleCancellation(request, request.cancelToken?.reason);
            return;
          }

          if (request.timeout != null) {
            request.timeoutTimer = Timer(request.timeout!, () {
              _handleTimeout(request);
            });
          }

          worker.sendRequest(<String, Object?>{
            'id': request.id,
            'channelName': request.channelName,
            'method': request.method,
            'arguments': request.arguments,
          });
        })
        .catchError((dynamic error) {
          if (_inFlight != request) return;
          request.completeError(error);
          _inFlight = null;
          _dispatchNext();
        });
  }

  static Future<_IsolateWorker> _ensureWorker() async {
    if (_worker != null) return _worker!;
    _worker = await _IsolateWorker.spawn(
      ServicesBinding.rootIsolateToken!,
      onResponse: _handleWorkerResponse,
    );
    return _worker!;
  }

  static void _handleWorkerResponse(dynamic message) {
    if (message is! Map) {
      _failInFlight(StateError('Background isolate returned $message'));
      return;
    }

    final id = message['id'] as int?;
    final request = _inFlight;
    if (request == null || id != request.id) {
      return;
    }

    request.clearListeners();
    request.timeoutTimer?.cancel();
    request.timeoutTimer = null;
    _inFlight = null;

    final ok = message['ok'] as bool? ?? false;
    if (ok) {
      request.complete(_fromSendable(message['result']) as Object?);
    } else {
      final exceptionType = message['exceptionType'] as String? ?? 'Error';
      if (exceptionType == 'PlatformException') {
        request.completeError(
          PlatformException(
            code: message['code'] as String? ?? 'unknown',
            message: message['message'] as String?,
            details: _fromSendable(message['details']),
          ),
        );
      } else {
        final error =
            message['error'] as String? ?? 'Unknown background isolate error';
        final stack = message['stack'] as String?;
        request.completeError(
          StateError(stack == null ? error : '$error\n$stack'),
        );
      }
    }

    _dispatchNext();
  }

  static void _handleCancellation(_PendingRequest request, String? reason) {
    if (_inFlight == request) {
      _restartWorker();
      request.completeError(CancelledException(reason));
      _inFlight = null;
      _dispatchNext();
      return;
    }

    if (_queue.remove(request)) {
      request.completeError(CancelledException(reason));
    }
  }

  static void _handleTimeout(_PendingRequest request) {
    if (_inFlight != request) return;

    _restartWorker();
    request.completeError(TimeoutException('Background call timed out'));
    _inFlight = null;
    _dispatchNext();
  }

  static void _failInFlight(Object error) {
    final request = _inFlight;
    if (request == null) return;

    request.completeError(error);
    _inFlight = null;
    _restartWorker();
    _dispatchNext();
  }

  static void _scheduleIdleShutdown() {
    _idleShutdownTimer?.cancel();
    _idleShutdownTimer = Timer(_idleShutdownDelay, () {
      if (_queue.isEmpty && _inFlight == null) {
        shutdown();
      }
    });
  }

  static Future<void> _restartWorker() async {
    await _shutdownWorker();
  }

  static Future<void> _shutdownWorker() async {
    final worker = _worker;
    _worker = null;
    if (worker == null) return;
    await worker.shutdown();
  }

  static Future<T?> _invokeOnCurrentIsolate<T>(
    String channelName,
    String method, {
    Map<String, dynamic>? arguments,
    CancelToken? cancelToken,
    Duration? timeout,
  }) async {
    if (cancelToken?.isCancelled ?? false) {
      throw CancelledException(cancelToken?.reason);
    }

    final channel = MethodChannel(channelName);
    final completer = Completer<T?>();
    var completed = false;

    void completeWithError(Object error, [StackTrace? stackTrace]) {
      if (completed) return;
      completed = true;
      completer.completeError(error, stackTrace);
    }

    void completeWithValue(T? value) {
      if (completed) return;
      completed = true;
      completer.complete(value);
    }

    void onCancel(String? reason) {
      completeWithError(CancelledException(reason));
    }

    cancelToken?.addListener(onCancel);

    var invokeFuture = channel.invokeMethod<T>(method, arguments);
    if (timeout != null) {
      invokeFuture = invokeFuture.timeout(timeout);
    }

    invokeFuture.then(completeWithValue).catchError(completeWithError);

    return completer.future.whenComplete(() {
      cancelToken?.removeListener(onCancel);
    });
  }
}

class _PendingRequest {
  final int id;
  final String channelName;
  final String method;
  final Map<String, dynamic>? arguments;
  final Completer<dynamic> completer;
  final CancelToken? cancelToken;
  final Duration? timeout;

  Timer? timeoutTimer;
  CancelListener? cancelListener;

  _PendingRequest({
    required this.id,
    required this.channelName,
    required this.method,
    required this.arguments,
    required this.completer,
    required this.cancelToken,
    required this.timeout,
  });

  void complete(Object? value) {
    clearListeners();
    if (!completer.isCompleted) {
      completer.complete(value);
    }
  }

  void completeError(Object error) {
    clearListeners();
    if (!completer.isCompleted) {
      completer.completeError(error);
    }
  }

  void clearListeners() {
    final listener = cancelListener;
    if (listener != null) {
      cancelToken?.removeListener(listener);
    }
    cancelListener = null;
    timeoutTimer?.cancel();
    timeoutTimer = null;
  }
}

class _IsolateWorker {
  final Isolate _isolate;
  final SendPort _requestPort;
  final ReceivePort _responsePort;
  final StreamSubscription<dynamic> _subscription;
  final ReceivePort _exitPort;

  _IsolateWorker._(
    this._isolate,
    this._requestPort,
    this._responsePort,
    this._subscription,
    this._exitPort,
  );

  static Future<_IsolateWorker> spawn(
    RootIsolateToken token, {
    required void Function(dynamic message) onResponse,
  }) async {
    final responsePort = ReceivePort();
    final readyPort = ReceivePort();
    final exitPort = ReceivePort();

    final isolate = await Isolate.spawn<_WorkerInitMessage>(
      _backgroundInvokeEntry,
      _WorkerInitMessage(
        readyTo: readyPort.sendPort,
        replyTo: responsePort.sendPort,
        token: token,
      ),
      onExit: exitPort.sendPort,
    );

    final requestPort = await readyPort.first as SendPort;
    readyPort.close();

    final subscription = responsePort.listen(onResponse);

    return _IsolateWorker._(
      isolate,
      requestPort,
      responsePort,
      subscription,
      exitPort,
    );
  }

  void sendRequest(Map<String, Object?> message) {
    _requestPort.send(message);
  }

  Future<void> shutdown() async {
    try {
      _requestPort.send(<String, Object?>{'type': 'shutdown'});
    } catch (_) {}

    _isolate.kill(priority: Isolate.immediate);
    await _subscription.cancel();
    _responsePort.close();
    _exitPort.close();
  }
}

class _WorkerInitMessage {
  final SendPort readyTo;
  final SendPort replyTo;
  final RootIsolateToken token;

  const _WorkerInitMessage({
    required this.readyTo,
    required this.replyTo,
    required this.token,
  });
}

Future<void> _backgroundInvokeEntry(_WorkerInitMessage init) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(init.token);

  final requestPort = ReceivePort();
  init.readyTo.send(requestPort.sendPort);

  await for (final message in requestPort) {
    if (message is! Map) continue;
    if (message['type'] == 'shutdown') {
      requestPort.close();
      Isolate.exit();
    }

    final id = message['id'] as int?;
    if (id == null) continue;

    final channelName = message['channelName'] as String?;
    final method = message['method'] as String?;
    if (channelName == null || method == null) continue;

    final arguments = _fromSendable(message['arguments']);

    try {
      final channel = MethodChannel(channelName);
      final result = await channel.invokeMethod<dynamic>(method, arguments);
      init.replyTo.send(<String, Object?>{
        'id': id,
        'ok': true,
        'result': _toSendable(result),
      });
    } on PlatformException catch (e, st) {
      init.replyTo.send(<String, Object?>{
        'id': id,
        'ok': false,
        'exceptionType': 'PlatformException',
        'code': e.code,
        'message': e.message,
        'details': _toSendable(e.details),
        'stack': st.toString(),
      });
    } catch (e, st) {
      init.replyTo.send(<String, Object?>{
        'id': id,
        'ok': false,
        'exceptionType': 'Error',
        'error': e.toString(),
        'stack': st.toString(),
      });
    }
  }
}

dynamic _toSendable(dynamic value) {
  if (value is Uint8List) {
    return TransferableTypedData.fromList(<Uint8List>[value]);
  }
  if (value is TransferableTypedData) {
    return value;
  }
  if (value is List) {
    return value.map(_toSendable).toList();
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key, _toSendable(item)));
  }
  return value;
}

dynamic _fromSendable(dynamic value) {
  if (value is TransferableTypedData) {
    return value.materialize().asUint8List();
  }
  if (value is List) {
    return value.map(_fromSendable).toList();
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key, _fromSendable(item)));
  }
  return value;
}
