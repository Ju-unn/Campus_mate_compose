import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 구매 버튼(pen Button `HE8FZ` 인스턴스: 높이 52 · 모서리 14 · 좌우 16 · 글자 16/700 · 앞 아이콘 20 + 간격 8).
/// 하단 바 `ipbPs` · 시트의 구매 `KuarM` · 취소 `IZFT1` 이 모두 이 버튼이다.
/// - 켜짐: primary 채움 + 흰 글자(15e-1 `g7Agjb` "100하트 받기 · 5,700원", 18d-1 "5,700원에 구매").
/// - 꺼짐([onPressed] null): 회색 #E5E5E5 + 글자 #929292(18d-3 `SjbFx` · 15e-3 `phlrb` · 15e-6 `SLjgz` · 15e-7 `xdQEp`).
/// - [neutral]: 회색 채움 + 글자 #222222(시트 "취소"). 꺼지면 글자만 #929292(18d-3 `UTe5A`).
/// - [busy]: 글자 앞에 도는 표시(pen 은 정지 아이콘 loader-circle — DESIGN §8.5 "도는 표시" 를 따른다, `LabeledField` 와 같다).
/// [expand] 가 true 면 가로를 채우고(시트), false 면 글자 폭 + 좌우 16 이다(하단 바). 글자가 칸보다 길면 줄이지 자르지 않는다.
class HeartPurchaseButton extends StatelessWidget {
  const HeartPurchaseButton({
    required this.label,
    required this.onPressed,
    this.expand = false,
    this.busy = false,
    this.neutral = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;
  final bool busy;
  final bool neutral;

  static const double height = 52;

  bool get _enabled => onPressed != null;

  Color get _fill => _enabled && !neutral ? AppColors.primary : AppColors.primaryDisabled;

  Color get _textColor {
    if (!_enabled) return AppColors.disabled;
    return neutral ? AppColors.ink : AppColors.onPrimary;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.button);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy) ...[
          const PurchaseSpinner(size: 20, color: AppColors.disabled),
          const SizedBox(width: AppSpacing.xs),
        ],
        Text(label, maxLines: 1, softWrap: false, style: AppTypography.button.copyWith(color: _textColor)),
      ],
    );
    final button = Material(
      color: _fill,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onPressed,
        child: SizedBox(
          height: height,
          width: expand ? double.infinity : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Center(
              widthFactor: expand ? null : 1,
              child: FittedBox(fit: BoxFit.scaleDown, child: content),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: button,
    );
  }
}

/// 진행 중 표시(선 두께 2 — 앱의 다른 작은 스피너와 같다). 움직임 줄이기가 켜져 있으면 돌지 않는 고리로 그린다(CLAUDE.md §7).
class PurchaseSpinner extends StatelessWidget {
  const PurchaseSpinner({required this.size, required this.color, super.key});

  final double size;
  final Color color;

  /// 움직임 줄이기에서 멈춰 보이는 고리의 길이(pen loader-circle 처럼 한쪽이 트인 모양).
  static const double _stillValue = 0.75;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(strokeWidth: 2, color: color, value: still ? _stillValue : null),
    );
  }
}
