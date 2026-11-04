import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/graduate/model/data/graduate_request_state.dart';
import 'package:campus_mate/graduate/view/graduate_reject_reason_text.dart';
import 'package:flutter/material.dart';

/// 테스트가 반려 알림을 찾는 표식.
const Key graduateRejectAlertKey = ValueKey('graduate-reject-alert');

/// 02-g-3 맨 위 반려 알림(pen `parki` · 마스터 `teNRJ` Alert, 18b-2 `kdibh` 복사). 본문 폭을 꽉 채우고 모서리가 없다.
/// 폭 fill · 아이콘과 글 사이 10 · 안쪽 [12,16] · 바탕 errorWash. 제목 14/600 error 줄높이 1.5, 캡션 12 muted 줄높이 1.5,
/// 두 줄 사이 2(PNG 실측 — 알림 높이 64.67 = 24 + 21 + 18 + 2).
class GraduateRejectAlert extends StatelessWidget {
  const GraduateRejectAlert({required this.reason, required this.attemptsLeft, super.key});

  final GraduateRejectReason? reason;

  /// 남은 신청 횟수. 캡션 끝에 "· 남은 신청 n번" 으로 붙는다(한 줄에 안 들어가면 캡션만 두 줄로 접힌다).
  final int attemptsLeft;

  /// 알림 둘째 줄(pen `Gmb1H`). 값표는 사유 하나(졸업증명서가 아니에요)만 그려서, 대장 결정(10-19)으로 모든 사유에 같은 줄을 쓰고
  /// 뒤에 남은 신청 횟수를 붙인다. 지원하지 않는 학교는 다시 올려 봐야 소용없어 다른 길을 알린다.
  String _caption(BuildContext context) {
    final l10n = context.l10n;
    return reason == GraduateRejectReason.schoolUnsupported
        ? l10n.graduateRejectCaptionUnsupported(attemptsLeft: attemptsLeft)
        : l10n.graduateRejectCaptionRetry(attemptsLeft: attemptsLeft);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // 서버가 모르는 사유 코드를 주었거나 사유가 비었을 때(`reason == null`)는 한 줄 제목만 — 값표에 없어 앱이 정한 문구다.
    final reason = this.reason;
    return Container(
      key: graduateRejectAlertKey,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(color: AppColors.errorWash),
      child: Row(
        children: [
          const Icon(AppIcons.alertTriangle, size: 20, color: AppColors.error),
          // pen 실측 10. 간격 토큰 xs(8)·sm(12) 사이 값이라 토큰으로 갈음하지 않는다(18b-2 와 같다).
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reason == null ? l10n.graduateRejectTitleUnknown : l10n.graduateRejectTitle(reason: reason.label(l10n)),
                  style: AppTypography.labelSmall.copyWith(color: AppColors.error, height: 1.5),
                ),
                const SizedBox(height: 2),
                Text(_caption(context), style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
