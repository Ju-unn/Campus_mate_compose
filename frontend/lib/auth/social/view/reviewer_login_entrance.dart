import 'package:campus_mate/auth/social/model/data/tap_streak.dart';
import 'package:flutter/material.dart';

/// 구글 플레이 심사원 로그인 창으로 들어가는 숨은 입구 — 놓인 자리를 빠르게 [TapStreak.taps] 번 누르면 [onOpen] 을 부른다.
///
/// 화면에는 아무것도 그리지 않는다. 투명해서(`translucent`) 입구 위를 끄는 손길은 밑의 스크롤이 그대로 받는다
/// (탭만 입구가 받으므로, 밑에 눌러야 하는 것이 있는 자리에는 놓지 않는다).
/// 일반 사용자에게 보이지 않는 기능이라 낭독기(접근성 트리)에서도 뺀다. 디버그 · 빌드 값 조건은 두지 않는다 —
/// 심사원이 스토어에서 받은 릴리스 빌드에서도 열려야 한다.
class ReviewerLoginEntrance extends StatefulWidget {
  const ReviewerLoginEntrance({required this.onOpen, super.key});

  final VoidCallback onOpen;

  @override
  State<ReviewerLoginEntrance> createState() => _ReviewerLoginEntranceState();
}

class _ReviewerLoginEntranceState extends State<ReviewerLoginEntrance> {
  final TapStreak _streak = TapStreak();

  void _onTap() {
    if (_streak.register(DateTime.now())) {
      widget.onOpen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onTap: _onTap,
    );
  }
}
