import 'package:campus_mate/core/haptics/haptics_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// [platform] 에서 기본 구현의 탭 전환 진동을 한 번 울리고, 플랫폼 채널로 나간 호출을 (메서드, 인자) 로 돌려준다.
Future<List<(String, Object?)>> _tabChangeCallsOn(TargetPlatform platform) async {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final container = ProviderContainer();
  addTearDown(container.dispose);

  await container.read(hapticsGatewayProvider).selectionClick();

  return calls.map((c) => (c.method, c.arguments)).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 안드로이드 엔진은 인자 없는 vibrate 를 LONG_PRESS 로 보낸다(PlatformPlugin.vibrateHapticFeedback).
  // 삼성 DC 모터 기기는 LONG_PRESS 말고는 진동을 내지 않는다(selectionClick=CLOCK_TICK, mediumImpact=KEYBOARD_TAP 도 버린다).
  test('안드로이드에서는 종류 인자 없는 vibrate(LONG_PRESS)를 한 번 보낸다', () async {
    expect(await _tabChangeCallsOn(TargetPlatform.android), [('HapticFeedback.vibrate', null)]);
  });

  test('iOS 에서는 selectionClick 진동을 한 번 보낸다', () async {
    expect(
      await _tabChangeCallsOn(TargetPlatform.iOS),
      [('HapticFeedback.vibrate', 'HapticFeedbackType.selectionClick')],
    );
  });
}
