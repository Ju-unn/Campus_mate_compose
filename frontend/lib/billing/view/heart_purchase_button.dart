import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 구매 버튼의 글자. 실결제를 열 때 바꿀 곳은 이 상수와 [HeartPurchaseButton] 을 쓰는 두 자리(하단 구매바 · 구매 확인 시트)의
/// `onPressed` 뿐이다. 지금은 결제가 없어 pen 대로 회색 "곧 열려요"(하단 바 `ipbPs` · 시트 `wM0FS`).
const String heartPurchaseLabel = '곧 열려요';

/// 구매 버튼(pen HE8FZ 인스턴스: 높이 52 · 모서리 14 · 채움 #E5E5E5 · 글자 16/700 #929292).
/// 회색이어도 누를 수는 있다 — 하단 바의 버튼이 구매 확인 시트를 여는 입구이기 때문이다.
/// [expand] 가 true 면 가로를 채우고(시트), false 면 글자 폭 + 좌우 16 이다(하단 바 96).
class HeartPurchaseButton extends StatelessWidget {
  const HeartPurchaseButton({
    required this.onPressed,
    this.label = heartPurchaseLabel,
    this.expand = false,
    this.textColor = AppColors.disabled,
    super.key,
  });

  final VoidCallback onPressed;
  final String label;
  final bool expand;

  /// 글자색. 회색 "곧 열려요"(#929292)가 기본이고, 시트의 "취소"(pen `KAUyy`)는 ink(#222222)로 쓴다.
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    final button = Material(
      color: AppColors.primaryDisabled,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onPressed,
        child: SizedBox(
          height: 52,
          width: expand ? double.infinity : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              widthFactor: expand ? null : 1,
              child: Text(label, style: AppTypography.button.copyWith(color: textColor)),
            ),
          ),
        ),
      ),
    );
    return Semantics(button: true, label: label, excludeSemantics: true, onTap: onPressed, child: button);
  }
}
