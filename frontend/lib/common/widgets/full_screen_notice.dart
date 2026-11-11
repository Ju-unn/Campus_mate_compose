import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 큰 안내 화면의 본문 틀(pen 알림 불러오기 실패 `vGd3l` · 인터넷 없음 `NWGuf` · 업데이트 필요 `zSzOG`):
/// 바깥 여백 [0,24,40,24] 안에서 안내([notice], 위 120 + 간격 20 아래에서 시작)는 스크롤 칸에 놓고,
/// 풀폭 [button] 은 바닥에 붙인다(버튼 위 20). 글자를 키운 기기에서는 안내만 스크롤하고 버튼은 바닥에 남는다.
/// Scaffold · 안전 영역은 쓰는 화면이 정한다.
class FullScreenNotice extends StatelessWidget {
  const FullScreenNotice({required this.notice, required this.button, this.regionBuilder, super.key});

  /// 보통 `EmptyNotice(align: EmptyNoticeAlign.top)`.
  final Widget notice;
  final Widget button;

  /// 안내 칸(버튼 위 20 포함)을 한 겹 더 감싼다. 업데이트 화면이 토스트 층을 얹는 데 쓴다.
  final Widget Function(Widget region)? regionBuilder;

  /// pen 위 여백(`MfW5m` 120) + 요소 사이 간격 20 → 안내 시작. 간격 20 은 토큰(md 16 · lg 24) 사이 값이다.
  static const double _gap = 20;
  static const double _topInset = 120;
  static const double _bottomInset = 40;

  @override
  Widget build(BuildContext context) {
    final region = Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.only(top: _topInset + _gap), child: notice),
      ),
    );
    final wrap = regionBuilder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, _bottomInset),
      child: Column(children: [Expanded(child: wrap == null ? region : wrap(region)), button]),
    );
  }
}
