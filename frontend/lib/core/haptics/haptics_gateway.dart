import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 기기 진동. 위젯이 [HapticFeedback] 을 바로 부르지 않고 이 층을 거쳐, 시험에서 Fake 로 바꿔 끼운다.
abstract interface class HapticsGateway {
  /// 고르는 것이 바뀌었다는 짧은 진동(안드로이드 · iOS 공통 — 탭 전환, pen `xtj0K` context).
  Future<void> selectionClick();
}

/// 플랫폼 진동을 그대로 부른다.
class PlatformHapticsGateway implements HapticsGateway {
  const PlatformHapticsGateway();

  @override
  Future<void> selectionClick() => HapticFeedback.selectionClick();
}

final hapticsGatewayProvider = Provider<HapticsGateway>((ref) => const PlatformHapticsGateway());
