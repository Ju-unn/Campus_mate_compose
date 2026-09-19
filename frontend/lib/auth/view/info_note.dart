import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 폼 아래에 붙는 한 줄 안내 카드 — `primary-wash` 채움 + 아이콘 + 설명.
///
/// 화면 3b 의 비공개 안내(pen `e2lP0i`)와 3c 의 공개 범위 안내(pen `Ado4S`)가 규격이 같아
/// 색·간격을 여기 한 곳에서만 정한다. 공개/비공개 어느 쪽이든 "읽고 지나가야 하는 정보"라
/// 아이콘만 `primary-text` 로 세우고 글자는 본문 톤으로 둔다.
class InfoNote extends StatelessWidget {
  const InfoNote({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // pen 실측 14. 간격 토큰 sm(12)·md(16) 사이 값이라 토큰으로 갈음하지 않는다
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: _content(),
    );
  }

  Widget _content() {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primaryText),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(text, style: AppTypography.bodySmall.copyWith(color: AppColors.body)),
        ),
      ],
    );
  }
}
