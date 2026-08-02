import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

typedef QqNativeMethodHandler =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> arguments);

class QqNativeBridge {
  QqNativeBridge({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    bool? isAndroid,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel('com.mkdjj.whisnya/qq_bridge'),
       _eventChannel =
           eventChannel ?? const EventChannel('com.mkdjj.whisnya/qq_status'),
       isAndroid = isAndroid ?? Platform.isAndroid;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final bool isAndroid;
  final _captured = StreamController<Map<String, dynamic>>.broadcast();
  QqNativeMethodHandler? onIncomingNotification;
  QqNativeMethodHandler? onRuntimeControl;

  Stream<Map<String, dynamic>> get capturedNotifications => _captured.stream;
  Stream<Map<String, dynamic>> get statusEvents => isAndroid
      ? _eventChannel
            .receiveBroadcastStream()
            .where((event) => event is Map<Object?, Object?>)
            .cast<Map<Object?, Object?>>()
            .map(_stringMap)
      : const Stream<Map<String, dynamic>>.empty();

  void initialize() {
    if (!isAndroid) return;
    _methodChannel.setMethodCallHandler((call) async {
      final arguments = call.arguments is Map<Object?, Object?>
          ? _stringMap(call.arguments as Map<Object?, Object?>)
          : <String, dynamic>{};
      switch (call.method) {
        case 'qqIncomingNotification':
          return (await onIncomingNotification?.call(arguments)) ??
              const {'status': 'ignored'};
        case 'qqNotificationCaptured':
          _captured.add(arguments);
          return const {'status': 'ignored'};
        case 'qqRuntimeControl':
          return (await onRuntimeControl?.call(arguments)) ??
              const {'status': 'ignored'};
        default:
          return null;
      }
    });
  }

  Future<Map<String, dynamic>> getNativeStatus() async {
    if (!isAndroid) return const {'supported': false};
    final value = await _methodChannel.invokeMapMethod<String, dynamic>(
      'getNativeStatus',
    );
    return value ?? const {};
  }

  Future<void> startForegroundBridge() => _invoke('startForegroundBridge');
  Future<void> stopForegroundBridge() => _invoke('stopForegroundBridge');
  Future<void> openNotificationListenerSettings() =>
      _invoke('openNotificationListenerSettings');
  Future<void> openAccessibilitySettings() =>
      _invoke('openAccessibilitySettings');
  Future<void> openBatteryOptimizationSettings() =>
      _invoke('openBatteryOptimizationSettings');
  Future<void> openAppNotificationSettings() =>
      _invoke('openAppNotificationSettings');
  Future<void> beginNotificationCapture() =>
      _invoke('beginNotificationCapture');
  Future<void> cancelNotificationCapture() =>
      _invoke('cancelNotificationCapture');
  Future<void> cancelPendingAccessibilityReply() =>
      _invoke('cancelPendingAccessibilityReply');

  Future<bool> isNotificationAccessGranted() =>
      _invokeBool('isNotificationAccessGranted');
  Future<bool> isAccessibilityServiceEnabled() =>
      _invokeBool('isAccessibilityServiceEnabled');
  Future<bool> isQqInstalled() => _invokeBool('isQqInstalled');

  Future<void> updateNativeQqSettings(Map<String, dynamic> settings) =>
      _invoke('updateNativeQqSettings', settings);

  Future<void> _invoke(String method, [Object? arguments]) async {
    if (!isAndroid) return;
    await _methodChannel.invokeMethod<void>(method, arguments);
  }

  Future<bool> _invokeBool(String method) async {
    if (!isAndroid) return false;
    return await _methodChannel.invokeMethod<bool>(method) ?? false;
  }

  static Map<String, dynamic> _stringMap(Map<Object?, Object?> value) => {
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}
