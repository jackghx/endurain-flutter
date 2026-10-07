import 'package:endurain/features/activity/services/activity_upload_queue.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lets the iOS host drain the upload queue from a `BGAppRefreshTask`.
///
/// The native side (see `AppDelegate.swift`) invokes `drain` when iOS grants
/// background time to a suspended app. The reply is `true` while failed uploads
/// remain, so the host schedules another refresh; `false` when the queue is
/// settled. Nothing invokes the channel on other platforms.
class BackgroundUploadChannel {
  BackgroundUploadChannel({
    required ActivityUploadQueue queue,
    MethodChannel channel = const MethodChannel(channelName),
  }) : _queue = queue,
       _channel = channel;

  static const String channelName = 'endurain/background_upload';
  static const String drainMethod = 'drain';

  final ActivityUploadQueue _queue;
  final MethodChannel _channel;

  void attach() => _channel.setMethodCallHandler(handleMethodCall);

  void detach() => _channel.setMethodCallHandler(null);

  @visibleForTesting
  Future<Object?> handleMethodCall(MethodCall call) async {
    if (call.method != drainMethod) {
      throw MissingPluginException('Unknown method ${call.method}');
    }
    await _queue.drain();
    return _queue.hasPendingRetry;
  }
}
