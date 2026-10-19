import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 테스트가 카드 상자를 찾는 열쇠.
const Key limitedContactsNoticeCardKey = ValueKey('limitedContactsNoticeCard');

/// 8d "일부 연락처만 허용" 안내 카드(pen `KvQom` — 원본 8d `bWKuJ`, 그림 `8d_일부_연락처만_허용.png`).
/// 바깥 여백 [8,24,12,24] → 카드(폭 fill · 세로 간격 6 · 여백 [14,16] · 모서리 12 · #F7F7F7, 테두리 없음).
/// 제목 줄(간격 6): 파란 안내 3D 아이콘 18 + 14/600 ink. 설명 12/400 muted 줄높이 1.5.
/// 아래 보조 단추: 높이 44 · 글자 폭 · 흰 바탕 · hairline 1px · 모서리 14 · 14/600 ink.
class LimitedContactsNotice extends StatelessWidget {
  const LimitedContactsNotice({required this.onOpenSettings, super.key});

  /// "기기 설정 열기" 를 눌렀다.
  final VoidCallback onOpenSettings;

  /// pen: 카드 gap 6 + 투명 Spacer 6 + gap 6 = 18(카드 높이 151). 간격 토큰에 18 이 없어 리터럴이다.
  static const double _descriptionToButton = 18;

  /// pen 여백 14 는 간격 토큰(sm 12 · md 16) 사이 값이다.
  static const double _cardVerticalPadding = 14;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
      child: Container(
        key: limitedContactsNoticeCardKey,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: _cardVerticalPadding, horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          // pen 모서리 12 는 라운드 토큰(sm 8 · md 14) 사이 값이다(검색칸과 같은 input).
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TitleRow(),
            const SizedBox(height: 6),
            Text(
              '목록에 보이지 않는 지인이 있다면 기기 설정에서 전체로 바꿔 주세요.',
              style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: _descriptionToButton),
            _SettingsButton(onPressed: onOpenSettings),
          ],
        ),
      ),
    );
  }
}

/// 제목 줄. 줄높이는 pen 에 속성이 없고 렌더가 ≈19.6(14 × 1.4)이라 1.4 로 둔다.
class _TitleRow extends StatelessWidget {
  const _TitleRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon3d(AppIcon3d.infoBlue, size: 18),
        const SizedBox(width: 6),
        Expanded(
          // 낭독기가 카드의 제목으로 읽게 한다.
          child: Semantics(
            header: true,
            child: Text(
              '일부 연락처만 허용돼 있어요',
              style: AppTypography.labelSmall.copyWith(color: AppColors.ink, height: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

/// 흰 바탕 · 테두리 보조 단추. 앱에는 이 모양의 공용 단추가 아직 없어(`AppButton` 보조는 회색 채움) 여기서만 쓴다.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = AppTypography.labelSmall.copyWith(color: AppColors.ink);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        // 높이 44 는 최소값이다 — 글자를 키우면 단추가 따라 커진다. 손가락 영역도 44 로 맞춘다.
        minimumSize: const Size(0, 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        textStyle: label,
        side: const BorderSide(color: AppColors.hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
      ),
      child: Text('기기 설정 열기', style: label),
    );
  }
}
