import 'package:campus_mate/chat/model/message.dart';
import 'package:campus_mate/chat/view/message_bubble.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 상대 말풍선을 길게 눌렀을 때(pen `I8fOcN`). 막을 깔고 **고른 말풍선만 막 위에 한 번 더 그려** 밝게 남긴 뒤
/// 그 바로 아래 8 에 팝업을 띄운다(pen `QkIPD` 는 색을 바꾸지 않은 같은 인스턴스다).
///
/// [bubbleContext] 는 말풍선 행(시각 포함) 자리를 재는 데 쓴다. "이 메시지 신고"를 누르면 true.
Future<bool> showBubbleReportMenu(BuildContext bubbleContext, Message message) async {
  final box = bubbleContext.findRenderObject()! as RenderBox;
  final row = box.localToGlobal(Offset.zero) & box.size;
  final picked = await showGeneralDialog<bool>(
    context: bubbleContext,
    barrierDismissible: true,
    barrierLabel: '닫기',
    barrierColor: AppColors.scrim,
    transitionDuration: AppMotion.press,
    pageBuilder: (context, _, _) => _BubbleMenuLayer(row: row, message: message),
  );
  return picked ?? false;
}

class _BubbleMenuLayer extends StatelessWidget {
  const _BubbleMenuLayer({required this.row, required this.message});

  /// 말풍선 행의 화면 좌표.
  final Rect row;
  final Message message;

  /// pen 팝업 높이(`F3325` 60). 아래 자리가 모자란지 가늠하는 데만 쓴다.
  static const double _menuHeight = 60;

  /// pen 말풍선 행 아래 끝과 팝업 사이 8.
  static const double _gap = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // pen 은 아래만 그렸다. 화면 맨 아래 말풍선이면 팝업이 화면 밖으로 나가 누를 수 없어 위로 뒤집는다.
    final fitsBelow =
        row.bottom + _gap + _menuHeight <= screen.height - MediaQuery.paddingOf(context).bottom;
    // 빈 자리는 막(barrier)이 받도록 투명 Material 로만 감싼다 — 글자 기본 스타일을 주는 용도다.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned(
            left: row.left,
            top: row.top,
            width: row.width,
            child: IgnorePointer(child: MessageBubble(message: message, isMine: false)),
          ),
          Positioned(
            left: row.left,
            top: fitsBelow ? row.bottom + _gap : null,
            bottom: fitsBelow ? null : screen.height - row.top + _gap,
            child: BubbleReportMenu(onReport: () => Navigator.of(context).pop(true)),
          ),
        ],
      ),
    );
  }
}

/// 팝업 카드(pen `F3325` = Popover · Bubble Menu `afUag`): 208 폭, 여백 4, 모서리 14, 행 하나.
class BubbleReportMenu extends StatelessWidget {
  const BubbleReportMenu({required this.onReport, super.key});

  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 208,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.md),
        // pen `afUag` 실측 그림자(#00000033, y 4, blur 16). 그림자 토큰(AppElevation.card)과 값이 달라 리터럴로 둔다.
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), offset: Offset(0, 4), blurRadius: 16),
        ],
      ),
      child: Semantics(
        button: true,
        // 눌림 효과가 팝업 안에서 그려지게 행 안에 Material 을 둔다(COMMON §4-2).
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onReport,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                child: Row(
                  children: [
                    const Icon(AppIcons.flag, size: 20, color: AppColors.ink),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '이 메시지 신고',
                        // pen `u6MbiB` 16 / normal, 줄높이 속성 없음 · 렌더 23.
                        style: AppTypography.body.copyWith(color: AppColors.ink, height: 23 / 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
