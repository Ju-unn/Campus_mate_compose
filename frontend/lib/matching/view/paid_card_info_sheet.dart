import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';

/// 결제 카드 물음표를 누르면 뜨는 "이렇게 정밀하게 골랐어요" 안내 시트(pen `EP8pA` → 시트 `sp1xa`, 값표 §6).
/// 문구는 pen 값표 그대로이고, 점수 숫자 · 순위 · 비중(30/20/50%) · 학교 이름은 이 시트에 없다.
Future<void> showPaidCardInfoSheet(BuildContext context) {
  return showSafetySheet<void>(context, (_) => const PaidCardInfoSheet());
}

/// 시트 틀은 안전 시트(`SafetySheet`, 여백 [12,20,28,20])와 안쪽 여백이 달라 따로 그린다.
/// pen: 손잡이 칸 28(padding [12,0]) + 내용 padding [8,16,32,16], 세로 gap 16.
/// 글자를 키우면 시트가 화면보다 길어지니 안쪽을 스크롤로 둔다.
class PaidCardInfoSheet extends StatelessWidget {
  const PaidCardInfoSheet({super.key});

  /// pen `sXtnP` 의 gap.
  static const double _gap = AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('paid-card-info-sheet'),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Handle(),
              Padding(
                // pen `sXtnP` padding [8,16,32,16].
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // pen `aaNm1` 20/700, 줄높이 속성 없음 · 렌더 29.
                    Text(
                      '이렇게 정밀하게 골랐어요',
                      style: AppTypography.navTitle.copyWith(color: AppColors.ink, height: 29 / 20),
                    ),
                    const SizedBox(height: _gap),
                    // pen `du9NW` 14/400/1.55 #6A6A6A.
                    Text(
                      '내 프로필과 상대 프로필을 네 가지로 나눠 비교해 점수를 매겼어요.',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: _gap),
                    const _ReasonRow(
                      icon: AppIcon3d.chat,
                      title: '성향 9가지 비교',
                      description: '집콕·밖으로부터 익숙한 것·새로운 것까지 설문 답을 하나하나 비교해요',
                    ),
                    const SizedBox(height: _gap),
                    const _ReasonRow(
                      icon: AppIcon3d.tags,
                      title: '관심사와 특징 태그',
                      description: '겹치는 관심사가 많을수록 점수가 올라가요',
                    ),
                    const SizedBox(height: _gap),
                    const _ReasonRow(
                      icon: AppIcon3d.sparkles,
                      title: 'AI 글 분석',
                      description: "자기소개와 '이런 사람이 좋아요' 글의 의미를 AI가 서로 비교해요",
                    ),
                    const SizedBox(height: _gap),
                    const _ReasonRow(
                      icon: AppIcon3d.badgeCheck,
                      title: '원하는 조건 반영',
                      description: '나이·키·MBTI·흡연·종교 조건이 맞을수록 높게 쳐요',
                    ),
                    const SizedBox(height: _gap),
                    const _Highlight(),
                    const SizedBox(height: _gap),
                    KeyedSubtree(
                      key: const ValueKey('paid-card-info-confirm'),
                      child: AppButton(
                        label: '알겠어요',
                        trailingIcon: AppIcons.arrowRight,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `NB9LG` 손잡이 칸 360×28 — 손잡이 `EOSt5` 36×4 가 위에서 12.
class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(child: SheetHandle(key: ValueKey('paid-card-info-handle'))),
    );
  }
}

/// 이유 한 줄(pen `musvL` 등) — 아이콘 36×36, 글 상자는 오른쪽 12, 제목과 설명 사이 2.
class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.icon, required this.title, required this.description});

  final AppIcon3d icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon3d(icon, size: 36),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // pen 15/700/1.4 #222222 — 15 는 타이포 토큰에 없다(14 와 16 사이).
              Text(
                title,
                style: AppTypography.bodySmall.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              // pen 14/normal/1.45 #6A6A6A.
              Text(description, style: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: 1.45)),
            ],
          ),
        ),
      ],
    );
  }
}

/// `vMtVN` 강조 상자 — padding 14, 모서리 12, 채움 primary-wash. 안의 숨은 링크 잔재(`vI8C0`)는 옮기지 않는다.
class _Highlight extends StatelessWidget {
  const _Highlight();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('paid-card-info-highlight'),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          '이 분석으로 나와 가장 잘 맞는 사람들 가운데 한 명을 골랐어요',
          style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, height: 1.5, color: AppColors.ink),
        ),
      ),
    );
  }
}
