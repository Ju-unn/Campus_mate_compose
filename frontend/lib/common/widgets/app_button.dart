import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// DESIGN.md §8.3 버튼 종류. 화면은 [variant] 와 [onPressed](null = 비활성)만
/// 고르고, 색·라운드·라벨 크기는 여기서만 정한다.
/// [neutral] 은 탈퇴 시트의 회색 "영구 삭제"(pen `l44zcf` · `l1XDPi` · `FbrhB`) — #F2F2F2 · 글자 #222222 18/700 · 모서리 8.
enum AppButtonVariant { primary, secondary, text, danger, dangerStrong, neutral }

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.height,
    this.isLoading = false,
    this.trailingIcon,
    this.isInline = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;

  /// 목록 안 인라인 버튼만 다른 높이를 쓴다(§8.3 "인라인 버튼 높이 변형" — 수락함 행이 44dp).
  /// 비워 두면 전체 폭 버튼 규격(pen `HE8FZ` 52, text variant `rK7sg` 48)이다 — 2026-10-01 개편 전은 56.
  final double? height;

  /// 저장 중(나 탭 편집 계획서 D8, pen 06-1 예시 `k5Gv4l`) — 글자 자리에 20 스피너(`sMuCd`)를 돌리고 누름을 막는다.
  /// 채움은 평상시 색 그대로 둔다: 꺼진 회색 위에서는 흰 스피너가 보이지 않는다.
  final bool isLoading;

  /// 라벨 오른쪽 20×20 아이콘(간격 8). 결제 카드 안내 시트의 "알겠어요 →"(pen `yqPNS`)가 쓴다. 비워 두면 글자만이다.
  final IconData? trailingIcon;

  /// 줄 안 버튼(04-1 휴대폰 인증 "인증번호 받기" · "확인", pen `HE8FZ` 폭 fit · 안쪽 [0,16]): 폭을 라벨에 맞춘다.
  /// [isLoading] 이면 글자를 지우지 않고 꺼진 회색(#E5E5E5) 위에 20 스피너를 라벨 왼쪽(간격 8)에 두고 라벨을 disabled 색으로 남긴다
  /// (pen 보내는 중 ⑩ · 확인 중 ⑪). 끄면(기본) 지금까지와 같다.
  final bool isInline;

  bool get _isTextVariant => variant == AppButtonVariant.text;

  bool get _isNeutral => variant == AppButtonVariant.neutral;

  /// text variant 라벨(pen `rK7sg` 라벨 16/600).
  static final TextStyle _textLabel = AppTypography.button.copyWith(fontWeight: FontWeight.w600);

  /// neutral 라벨(pen `l44zcf` 18/700).
  static const TextStyle _neutralLabel = AppTypography.label;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: _styleFor(height ?? (_isTextVariant ? 48 : 52)),
      child: isLoading
          ? (isInline ? _inlineLoading() : _spinner())
          : _content(),
    );
  }

  Widget _content() {
    final text = Text(label, style: _isTextVariant ? _textLabel : (_isNeutral ? _neutralLabel : AppTypography.button));
    final icon = trailingIcon;
    if (icon == null) {
      return text;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Flexible(child: text), const SizedBox(width: 8), Icon(icon, size: 20)],
    );
  }

  /// 줄 안 버튼의 보내는 중 · 확인 중 — 스피너 20(선 2) → 8 → 라벨. 색은 꺼진 버튼의 글자색(disabled)이다.
  Widget _inlineLoading() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.disabled),
        ),
        const SizedBox(width: 8),
        Flexible(child: Text(label, style: AppTypography.button)),
      ],
    );
  }

  /// 글자가 빠져도 낭독기에는 버튼 이름이 들리게 스피너에 이름을 단다.
  /// 선 두께 2 는 앱의 다른 작은 스피너(`LabeledField` 확인 중)와 같게 둔 것 — pen `sMuCd` 값이 오면 다시 맞춘다(대장 09-28).
  Widget _spinner() {
    return SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: _idleForeground(), semanticsLabel: label),
    );
  }

  ButtonStyle _styleFor(double height) {
    final base = ElevatedButton.styleFrom(
      // 줄 안 버튼은 라벨 폭에 맞춘다 — 가로 최소를 무한으로 두면 Row 안에서 넓이를 정할 수 없다.
      minimumSize: Size(isInline ? 0 : double.infinity, height),
      maximumSize: Size(double.infinity, height),
      padding: isInline ? const EdgeInsets.symmetric(horizontal: 16) : EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_isNeutral ? AppRadius.sm : AppRadius.button)),
    );
    return base.copyWith(
      backgroundColor: _backgroundColor(),
      foregroundColor: _foregroundColor(),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    );
  }

  WidgetStateProperty<Color> _backgroundColor() {
    return WidgetStateProperty.resolveWith((states) {
      // 전체 폭 버튼은 흰 스피너가 보이게 평상시 채움을 둔다. 줄 안 버튼은 pen ⑩ ⑪ 대로 꺼진 회색이다.
      if (isLoading && !isInline) {
        return _idleBackground();
      }
      if (states.contains(WidgetState.disabled)) {
        return _isTextVariant ? Colors.transparent : AppColors.primaryDisabled;
      }
      if (states.contains(WidgetState.pressed)) {
        return variant == AppButtonVariant.primary
            ? AppColors.primaryPressed
            : AppColors.surfaceSoft;
      }
      return _idleBackground();
    });
  }

  Color _idleBackground() {
    return switch (variant) {
      AppButtonVariant.primary => AppColors.primary,
      AppButtonVariant.secondary => AppColors.primaryDisabled,
      AppButtonVariant.text => Colors.transparent,
      AppButtonVariant.danger => AppColors.primaryDisabled,
      AppButtonVariant.dangerStrong => AppColors.error,
      AppButtonVariant.neutral => AppColors.surfaceStrong,
    };
  }

  WidgetStateProperty<Color> _foregroundColor() {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return AppColors.disabled;
      }
      return _idleForeground();
    });
  }

  Color _idleForeground() {
    return switch (variant) {
      AppButtonVariant.primary => AppColors.onPrimary,
      AppButtonVariant.secondary => AppColors.ink,
      AppButtonVariant.text => AppColors.primaryText,
      AppButtonVariant.danger => AppColors.error,
      AppButtonVariant.dangerStrong => AppColors.onPrimary,
      AppButtonVariant.neutral => AppColors.ink,
    };
  }
}
