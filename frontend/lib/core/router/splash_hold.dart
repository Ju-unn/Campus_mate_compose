import 'dart:async';

import 'package:flutter/foundation.dart';

/// 스플래시 화면을 정해진 시간만큼 붙잡아 둔다.
///
/// **임시 장치다.** 세션 확인이 순식간에 끝나 스플래시가 눈에 보이지 않는데,
/// 앱 아이콘·로고가 정해질 때까지 화면이 뜨는지 눈으로 확인하려고 둔다
/// (2026-09-22 사용자 요청). 로고 작업 때 이 클래스째로 지운다.
///
/// 라우터의 `refreshListenable` 에 물려, 시간이 다 되면 이동 판단을 다시 시킨다.
class SplashHold extends ChangeNotifier {
  SplashHold({Duration duration = _defaultDuration}) {
    _timer = Timer(duration, _release);
  }

  static const _defaultDuration = Duration(seconds: 2);

  late final Timer _timer;
  bool _isHolding = true;

  /// 아직 스플래시에 머물러야 하는지.
  bool isHolding() => _isHolding;

  void _release() {
    _isHolding = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
