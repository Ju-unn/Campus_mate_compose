import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 기기 진동. 위젯이 [HapticFeedback] 을 바로 부르지 않고 이 층을 거쳐, 시험에서 Fake 로 바꿔 끼운다.
abstract interface class HapticsGateway {
  /// 고르는 것이 바뀌었다는 짧은 진동(탭 전환, pen `xtj0K` context). 플랫폼마다 실제 종류가 다르다.
  Future<void> selectionClick();
}

/// 플랫폼 진동을 부른다.
class PlatformHapticsGateway implements HapticsGateway {
  const PlatformHapticsGateway();

  /// iOS 는 selectionClick 그대로. 안드로이드는 [HapticFeedback.vibrate](LONG_PRESS)로 바꾼다.
  /// 삼성 DC 모터 기기(갤럭시 A 계열)는 앱이 보낸 performHapticFeedback 중 LONG_PRESS 만 진동으로 내고
  /// selectionClick(CLOCK_TICK) · lightImpact(VIRTUAL_KEY) · mediumImpact(KEYBOARD_TAP) · heavyImpact(CONTEXT_CLICK)는
  /// 받기만 하고 버린다(2026-10-14 SM-A826S 로그 · services.jar 확인). LONG_PRESS 도 사용자 터치 진동 설정은 따른다.
  @override
  Future<void> selectionClick() => switch (defaultTargetPlatform) {
    TargetPlatform.android => HapticFeedback.vibrate(),
    _ => HapticFeedback.selectionClick(),
  };
}

final hapticsGatewayProvider = Provider<HapticsGateway>((ref) => const PlatformHapticsGateway());
