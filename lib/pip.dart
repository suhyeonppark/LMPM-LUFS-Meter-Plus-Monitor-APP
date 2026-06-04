import 'dart:async';

import 'package:flutter/services.dart';

/// 안드로이드 Picture-in-Picture(화면 위에 떠 있는 작은 창) 제어.
///
/// 네이티브(MainActivity)가 채널을 처리하지 않으면(예: 데스크톱/웹, 구버전)
/// 조용히 "지원 안 함"으로 처리한다.
class PipController {
  PipController() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('lufs/pip');

  final _modeController = StreamController<bool>.broadcast();

  /// PiP 모드 진입/이탈 변화. `true` = 떠 있는 작은 창 상태.
  Stream<bool> get pipModeChanges => _modeController.stream;

  /// 이 기기에서 PiP 를 쓸 수 있는지(안드로이드 8.0+ & 기능 지원).
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 지금 즉시 떠 있는 작은 창으로 전환한다.
  Future<void> enter() async {
    try {
      await _channel.invokeMethod('enter');
    } catch (_) {
      // 지원하지 않으면 무시.
    }
  }

  /// iOS PiP 는 Flutter 화면을 그대로 띄울 수 없어 네이티브 쪽 작은 미터 화면에
  /// 최신 측정값을 따로 넘겨준다. Android 에서는 기존 화면 PiP 만 쓰므로 무시된다.
  Future<void> updateReading({
    double? momentary,
    double? shortTerm,
    double? integrated,
  }) async {
    try {
      await _channel.invokeMethod('updateReading', {
        'momentary': momentary,
        'shortTerm': shortTerm,
        'integrated': integrated,
      });
    } catch (_) {
      // PiP 채널이 없거나 지원하지 않는 플랫폼에서는 무시.
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'pipModeChanged') {
      _modeController.add(call.arguments == true);
    }
    return null;
  }

  void dispose() {
    _modeController.close();
  }
}
