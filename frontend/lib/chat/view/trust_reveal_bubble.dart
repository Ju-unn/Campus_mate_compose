import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 신뢰 확인을 통과한 뒤 대화 끝에 붙는 카드(화면 14b, pen `MAn9h`).
///
/// **"상대 프로필 보기"(14c) 버튼은 그리지 않는다** — 14c 는 지인 리뷰와 신고·차단이 섞인
/// 화면이라 통째로 뒤 조각이다. 카카오톡 아이디 복사까지가 이번 조각의 끝이다.
class TrustRevealBubble extends StatelessWidget {
  const TrustRevealBubble({required this.kakaoId, super.key});

  final String? kakaoId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.badgeCheck, size: 14, color: AppColors.primaryText),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                '신뢰 확인 완료',
                style: AppTypography.caption
                    .copyWith(color: AppColors.primaryText, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '서로 실제 프로필을 공개했어요',
            style: AppTypography.bodyStrong
                .copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          _KakaoRow(kakaoId: kakaoId),
        ],
      ),
    );
  }
}

class _KakaoRow extends StatelessWidget {
  const _KakaoRow({required this.kakaoId});

  final String? kakaoId;

  @override
  Widget build(BuildContext context) {
    final id = kakaoId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '카카오톡 아이디',
                  style: AppTypography.badge.copyWith(color: AppColors.muted),
                ),
                Text(
                  // 상대가 아직 아이디를 저장하지 않았을 수 있다 — 빈 칸을 그리지 않고 말로 적는다.
                  id ?? '상대가 아직 아이디를 등록하지 않았어요',
                  style: AppTypography.bodyStrong.copyWith(color: AppColors.ink),
                ),
              ],
            ),
          ),
          if (id != null)
            IconButton(
              icon: const Icon(AppIcons.copy, size: 18, color: AppColors.muted),
              tooltip: '복사',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: id));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('카카오톡 아이디를 복사했어요')));
                }
              },
            ),
        ],
      ),
    );
  }
}
