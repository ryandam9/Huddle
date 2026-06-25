import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the app process alive during a long transfer so a batch can keep
/// sending while the app is backgrounded.
///
/// Only Android can actually do this (via a foreground service); everywhere
/// else the implementation is a no-op. The interface is injectable so the
/// controller's start/stop orchestration can be unit-tested without a platform.
abstract class ForegroundService {
  /// Begin keeping the process alive, showing [message] in the ongoing
  /// notification.
  Future<void> start(String message);

  /// Stop keeping the process alive.
  Future<void> stop();
}

/// Drives an Android foreground service over a platform channel. A no-op on
/// non-Android platforms (and harmlessly swallows channel errors, e.g. when no
/// native handler is registered).
class AndroidForegroundService implements ForegroundService {
  static const MethodChannel _channel =
      MethodChannel('net.ryandam.huddle/foreground');

  @override
  Future<void> start(String message) => _invoke('start', {'message': message});

  @override
  Future<void> stop() => _invoke('stop', null);

  Future<void> _invoke(String method, Map<String, dynamic>? args) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod(method, args);
    } catch (_) {
      // The transfer still proceeds in the foreground; losing the keep-alive
      // notification shouldn't surface as an error to the user.
    }
  }
}
