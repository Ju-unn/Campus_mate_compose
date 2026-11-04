import 'package:flutter/foundation.dart';

/// 움직이는 그림(Lottie) 장면 하나 — json 경로와, 기기 "동작 줄이기" 일 때 멈춰서 보일 프레임.
///
/// 화면은 경로 글자를 직접 쓰지 않고 [AppLottie] 의 상수를 `AppLottieView` 에 넘긴다.
@immutable
class LottieScene {
  const LottieScene({required this.path, required this.stillFrame});

  /// 앱 asset 경로(`assets/lottie/<이름>.json`). 그림은 `assets/lottie/images/<이름>/` 에 둔다.
  final String path;

  /// "동작 줄이기" 일 때 보일 프레임 번호. json 의 `ip` 이상 `op` 미만이어야 한다.
  final double stillFrame;
}

/// 움직이는 그림 장면 표 (AppIcons 처럼 상수만). 색은 그림 속 색 그대로 쓴다(앱 토큰으로 바꾸지 않는다 — 2026-11-03 사용자 결정).
///
/// 새 장면을 더할 때: `assets/lottie/<이름>.json` 과 `assets/lottie/images/<이름>/` 를 넣고, json 의 그림 폴더(`assets[].u`)를
/// `images/<이름>/` 으로 맞추고, pubspec assets 에 그림 폴더를 적고, 여기에 한 줄을 더한다. `test/core/theme/app_lottie_test.dart` 가 지킨다.
abstract final class AppLottie {
  /// 01 스플래시 · 소셜 로그인(크리스마스 판, 360×780, 30fps, 0~303). 표시: intro 0~63, loop 64~303.
  static const LottieScene splashChristmas = LottieScene(path: 'assets/lottie/splash_christmas.json', stillFrame: 303);

  /// 05-12 아바타 생성 중(344×330, 0~120). 표시: loop 0~120.
  static const LottieScene avatarPainting = LottieScene(path: 'assets/lottie/avatar_painting.json', stillFrame: 0);

  /// 12 매칭 성사(300×250, 0~195). 표시: intro 0~45, loop 45~195. 멈춤은 마지막 프레임(194).
  static const LottieScene matchCelebration = LottieScene(path: 'assets/lottie/match_celebration.json', stillFrame: 194);

  /// 06-2b 진행 중 단계 표시(48×48, 0~36). 표시: loop 0~36.
  static const LottieScene brandSpinner = LottieScene(path: 'assets/lottie/brand_spinner.json', stillFrame: 0);

  /// 시험이 훑는 전체 표.
  static const List<LottieScene> values = [splashChristmas, avatarPainting, matchCelebration, brandSpinner];
}
