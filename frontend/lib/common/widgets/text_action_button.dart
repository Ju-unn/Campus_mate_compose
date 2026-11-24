import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 글자 버튼(datingApp.pen TextButton `UqCmR`: 14/600, 채움 · 밑줄 · 아이콘 없음). 높이 · 안쪽 여백 · 색은 쓰는 자리의 pen 인스턴스 값이다
/// — 04-1 "번호 바꾸기" 52 · [0,12], "다시 받기" 48 · 0, 02 "학교 추가 요청하기" 48 · 0(기본값). 폭은 글자만큼이라 정렬은 부모가 정한다.
/// 꺼지면([onPressed] null) 눌리지 않고 부른 쪽이 회색을 준다.
/// [MutedTextButton](muted 고정 · 늘 켜짐 · 가운데)과 AppButton text 변형(16/600)은 모양이 달라 따로 둔다.
class TextActionButton extends StatelessWidget {
  const TextActionButton({
    required this.label,
    required this.onPressed,
    this.color = AppColors.primaryText,
    this.height = 48,
    this.horizontalPadding = 0,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;

  /// 최소 높이 — 글자를 키우면 버튼이 따라 커진다.
  final double height;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Center(
                widthFactor: 1,
                child: Text(label, style: AppTypography.labelSmall.copyWith(color: color)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
