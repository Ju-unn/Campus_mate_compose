import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 채팅방 헤더 아래 배너(pen `teNRJ` Notice). 세 가지가 같은 자리를 쓴다 —
/// 미리 수락(pen 부품 `TrustPreAcceptBanner` `IhqF4`) · 14g 대기(`A1g5lB`) · 14h 종료 예정(`bAZox`).
class TrustBanner extends StatelessWidget {
  const TrustBanner({
    required this.title,
    required this.caption,
    this.isMuted = false,
    this.icon,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String caption;

  /// 종료 예정(14h)은 회색 바탕이다 — 좋은 소식이 아닌 자리에 분홍을 쓰지 않는다.
  final bool isMuted;

  /// 게이트가 아닌 배너(연결 끊김)가 같은 자리를 빌려 쓸 때만 넘긴다. 안 넘기면 게이트 아이콘.
  final IconData? icon;

  /// 미리 수락 배너에만 버튼이 있다. 거절 버튼은 두지 않는다 —
  /// 24시간 전의 거절은 되돌릴 수 없는데 얻는 게 없다(시트에서 충분히 고민한 뒤에 하면 된다).
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    // pen `IhqF4`(360×125): 안내 영역 [12,16,12,16] → 버튼 영역 [0,16,16,16]. 안내 영역 아래 12 가 곧 버튼 위 간격이다.
    // 버튼 없는 배너(14g · 14h · 연결 끊김)는 같은 안내 영역만 쓴다 — 그 pen 값(`A1g5lB` · `bAZox`)은 따로 대조하지 않았다.
    return Container(
      width: double.infinity,
      color: isMuted ? AppColors.surfaceSoft : AppColors.primaryWash,
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, actionLabel == null ? AppSpacing.sm : AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon ?? (isMuted ? AppIcons.timer : AppIcons.shieldCheck),
                size: 20,
                color: isMuted ? AppColors.muted : AppColors.primaryText,
              ),
              const SizedBox(width: 10), // pen 아이콘 → 글자 10 — 간격 토큰(8 · 12) 사이 값
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // pen 제목 14/600 · 줄높이 1.5, 설명 12/normal · 줄높이 1.5 — 토큰 줄높이(1.2 · 1.4)만 pen 값으로 바꾼다.
                    Text(
                      title,
                      style: AppTypography.labelSmall.copyWith(color: AppColors.ink, height: 1.5),
                    ),
                    const SizedBox(height: 2), // pen 제목 → 설명 2 — 간격 토큰(4)보다 작은 값
                    Text(
                      caption,
                      style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            // pen 328×44 primary · 모서리 14 · 라벨 16/700 = AppButton 기본(라벨 AppTypography.button 16/700, pen HE8FZ 개편 10-01).
            // frontend/CLAUDE.md §7 "버튼 라벨은 18/700" 과는 다르다 — 앱 버튼 전체가 16/700 이라 여기만 18 로 키우지 않는다(대장 보고).
            // 기본 누름 여백(48)을 붙이면 자리가 48 이 돼 배너가 129 가 된다 — pen 합계 125 에 맞춰 44 로 둔다
            // (폭 328 · 높이 44 = iOS 44pt 이상, 안드로이드 48dp 권장보다 4 작다 — 대장 보고).
            Theme(
              data: Theme.of(context).copyWith(materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: AppButton(label: actionLabel!, onPressed: onAction, height: 44),
            ),
          ],
        ],
      ),
    );
  }
}
