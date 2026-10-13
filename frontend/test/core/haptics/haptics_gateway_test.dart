import 'package:campus_mate/core/haptics/haptics_gateway.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('기본 구현은 플랫폼에 selectionClick 진동을 한 번 보낸다(안드로이드 · iOS 공통 채널)', () async {
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
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(hapticsGatewayProvider).selectionClick();

    expect(calls.map((c) => (c.method, c.arguments)), [('HapticFeedback.vibrate', 'HapticFeedbackType.selectionClick')]);
  });
}
