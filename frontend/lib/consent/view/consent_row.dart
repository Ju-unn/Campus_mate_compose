import 'package:campus_mate/common/widgets/app_checkbox.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 약관 동의 줄(pen 마스터 ConsentRow `rmMvJ` 꺼짐 · `jFMyA` 켜짐). 체크 영역과 "보기 ›" 사이 8.
/// 체크 영역: 위아래 12 · 간격 12 · [체크 24][뱃지][글]. 전체 동의는 같은 마스터에서 뱃지 · 보기를 끄고 17/600 이다.
class ConsentRow extends StatelessWidget {
  const ConsentRow({
    required this.label,
    required this.checked,
    required this.onToggle,
    this.isRequired,
    this.onView,
    this.isAllAgree = false,
    super.key,
  });

  final String label;
  final bool checked;
  final VoidCallback onToggle;

  /// 뱃지. null 이면 뱃지가 없다(전체 동의).
  final bool? isRequired;

  /// "보기 ›". null 이면 없다(전체 동의 · 마케팅).
  final VoidCallback? onView;
  final bool isAllAgree;

  @override
  Widget build(BuildContext context) {
    final required = isRequired;
    // 잉크는 가장 가까운 Material 에 그린다 — Scaffold 에 그리면 본문을 밀어도 눌림이 제자리에 뜬다(COMMON §4-2).
    return Material(
      type: MaterialType.transparency,
      child: Row(
        children: [
          Expanded(
            child: MergeSemantics(
              child: Semantics(
                checked: checked,
                child: InkWell(
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Row(
                      children: [
                        AppCheckbox(checked: checked),
                        const SizedBox(width: AppSpacing.sm),
                        if (required != null) ...[_Badge(isRequired: required), const SizedBox(width: AppSpacing.sm)],
                        Expanded(
                          child: Text(
                            label,
                            style: (isAllAgree ? AppTypography.subtitle : AppTypography.body)
                                .copyWith(color: AppColors.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onView case final onView?) ...[
            const SizedBox(width: AppSpacing.xs),
            _ViewButton(label: label, onPressed: onView),
          ],
        ],
      ),
    );
  }
}

/// 필수 · 선택 뱃지(pen Badge · Text `Aioxz`). 알약 · 여백 [2,6] · 11/700.
class _Badge extends StatelessWidget {
  const _Badge({required this.isRequired});

  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isRequired ? AppColors.primaryWash : AppColors.surfaceStrong,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      // pen `klkPA` 글자 칸 16 — badge 토큰 줄높이(1.3)면 알약이 20 보다 얇아진다(heart_task_row 와 같은 값).
      child: Text(
        isRequired ? '필수' : '선택',
        style: AppTypography.badge.copyWith(
          fontWeight: FontWeight.w700,
          color: isRequired ? AppColors.primaryText : AppColors.muted,
          height: 16 / 11,
        ),
      ),
    );
  }
}

/// "보기 ›"(pen `y0U7f`). 높이 48 · 왼쪽 8 · 간격 2. 노션 약관의 그 항을 기기 브라우저로 연다.
class _ViewButton extends StatelessWidget {
  const _ViewButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // "보기"만 읽으면 어느 약관인지 모른다 — 줄 글을 붙여 읽는다.
      label: '${label.replaceAll('\n', ' ')} 보기',
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('보기', style: AppTypography.bodySmall.copyWith(color: AppColors.muted)),
                const SizedBox(width: 2),
                const Icon(AppIcons.chevronRight, size: 20, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
