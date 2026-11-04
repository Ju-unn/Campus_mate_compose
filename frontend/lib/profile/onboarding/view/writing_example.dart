import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// "이렇게 적어요" 작성 예시(pen 마스터 `WritingExample`, 대장 전달 값). 자유 글 칸(06-2a · 06-3) 아래에 예시 문장 카드를 쌓는다.
/// 캡션 14/400 #3F3F3F, 카드 #F7F7F7 · 모서리 12 · 안쪽 [12,14] · 카드 사이 8, 문장 14/400 · 줄높이 1.55 #3F3F3F.
class WritingExample extends StatelessWidget {
  const WritingExample({required this.sentences, super.key});

  final List<String> sentences;

  /// 대장 값 모서리 12 는 토큰 sm(8) · md(14) 사이라 그대로 쓴다(안내 카드 기본형과 같은 값).
  static const double _radius = 12;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodySmall.copyWith(color: AppColors.body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('이렇게 적어요', style: style),
        // 캡션 ↔ 첫 카드 8 — 대장 값에 없어 카드 사이와 같게 둔다(pen 확인 대상).
        const SizedBox(height: AppSpacing.xs),
        for (final (index, sentence) in sentences.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: 14),
            decoration: BoxDecoration(color: AppColors.surfaceSoft, borderRadius: BorderRadius.circular(_radius)),
            child: Text(sentence, style: style),
          ),
        ],
      ],
    );
  }
}
