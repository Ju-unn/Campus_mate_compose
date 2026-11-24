import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// 목록 한 줄 + 그 아래 버튼 띠. 대화 탭의 두 목록이 같이 쓴다 — 보낸 신청 · 프로필 보기(pen INViw: 줄 → 8 → 버튼 하나,
/// 거절됨 H75rq 는 아래 12 를 더함)와 거절한 카드 줄(pen pdOvf: 줄 → 12 → [프로필 보기] + [다시 신청하기], 사이 8).
/// 둘 다 matching 기능(대화 탭) 안이라 common 이 아니라 여기 둔다. 버튼은 AppButton 작은 크기를 넘긴다(대장 판정 6).
///
/// 버튼들은 한 줄에 같은 폭으로 선다. 줄의 눌림 · 모양은 [row] 가 정하고 이 위젯은 배치만 한다.
class RowWithActions extends StatelessWidget {
  const RowWithActions({
    required this.row,
    required this.actions,
    this.gap = AppSpacing.xs,
    this.bottomPadding = 0,
    super.key,
  });

  /// 위 줄(예: pen SentRequestRow d6otzp).
  final Widget row;

  /// 아래 버튼들. 왼쪽부터 같은 폭으로, 사이 8(pen pdOvf Buttons `c3jmv` gap 8).
  final List<Widget> actions;

  /// 줄 → 버튼 띠 간격(INViw 8 · pdOvf 12).
  final double gap;

  /// 버튼 띠 아래 여백(H75rq padding 아래 12, INViw · pdOvf 0).
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          SizedBox(height: gap),
          Row(
            spacing: AppSpacing.xs,
            children: [for (final action in actions) Expanded(child: action)],
          ),
        ],
      ),
    );
  }
}
