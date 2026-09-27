import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 신뢰 확인을 통과한 뒤 대화 끝에 붙는 카드(화면 14b, pen `MAn9h`).
///
/// 카드 맨 아래 "상대 프로필 보기"(pen `vmfRQ`)가 14c 상대 프로필 상세로 간다(조각 6).
/// 어디로 갈지는 부른 쪽(채팅방)이 정한다 — 카드는 상대 id 를 모른다.
class TrustRevealBubble extends StatelessWidget {
  const TrustRevealBubble({required this.kakaoId, required this.onViewProfile, super.key});

  static const double _gap = 10;

  /// "상대 프로필 보기" 누르는 영역 48 = 보이는 44 + 위아래 2. 그 2 는 버튼 위 간격과 카드 아래 여백에서
  /// 가져온다 — 카드 높이와 다른 요소 자리는 그대로다.
  static const double _buttonBleed = 2;

  final String? kakaoId;
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md - _buttonBleed,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // pen `ha583`: shield-check 14 + 12/600, 간격 6(간격 토큰 xxs 4 · xs 8 사이 값).
          Row(
            children: [
              const Icon(AppIcons.shieldCheck, size: 14, color: AppColors.primaryText),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '신뢰 확인 완료',
                  // 줄높이 속성 없음 · pen 렌더 17.
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w600,
                    height: 17 / 12,
                  ),
                ),
              ),
            ],
          ),
          // pen 카드 간격 10(`MAn9h` gap) — 배지 · 제목 · 카톡 행 · 버튼 사이 모두. 간격 토큰 xs(8)·sm(12) 사이 값이다.
          const SizedBox(height: _gap),
          Text(
            '서로 실제 프로필을 공개했어요',
            // pen `lIf91` 16/700, 줄높이 1.4 · 렌더 23(카톡 행이 그 23 뒤 10 에 놓인다).
            style: AppTypography.bodyStrong
                .copyWith(color: AppColors.ink, fontWeight: FontWeight.w700, height: 23 / 16),
          ),
          const SizedBox(height: _gap),
          _KakaoRow(kakaoId: kakaoId),
          const SizedBox(height: _gap - _buttonBleed),
          _ViewProfileButton(onPressed: onViewProfile),
        ],
      ),
    );
  }
}

/// "상대 프로필 보기"(pen `vmfRQ`, MAn9h 마스터 안 plain frame): 296×44, 모서리 12, 주색,
/// 16/700 흰 글자 + chevron-right 16. 높이는 최소값만 걸어 글자를 키우면 따라 커진다.
///
/// 누르는 영역은 위아래 [TrustRevealBubble._buttonBleed] 씩 넓혀 48 이다(DESIGN §10). 넓힌 띠를 누르면
/// 잉크 없이 바로 연다 — 잉크는 보이는 버튼 모양(Material) 안에서만 번진다(COMMON §4-2).
/// 버튼 안을 누르면 안쪽 InkWell 이 제스처를 이겨 한 번만 불린다.
class _ViewProfileButton extends StatelessWidget {
  const _ViewProfileButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 읽어 주는 버튼은 안쪽 하나뿐이다.
      excludeFromSemantics: true,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: TrustRevealBubble._buttonBleed),
        child: _visibleButton(),
      ),
    );
  }

  Widget _visibleButton() {
    return Semantics(
      button: true,
      // 눌림 효과가 대화 목록과 같이 움직이게 버튼 안에 Material 을 둔다(COMMON §4-2).
      child: Material(
        color: AppColors.primary,
        // pen 모서리 12 는 라운드 토큰(sm 8 · md 14) 사이 값이다.
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      '상대 프로필 보기',
                      style: AppTypography.bodyStrong
                          .copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  // pen 간격 6. 간격 토큰 xxs(4)·xs(8) 사이 값이다.
                  const SizedBox(width: 6),
                  const Icon(AppIcons.chevronRight, size: 16, color: AppColors.onPrimary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 카톡 행(pen `I9ZyOV`): 296×60, 여백 [10,12], 모서리 10, 흰 바탕. 라벨 11 · 값 16/600, 사이 2. 복사 copy 18.
class _KakaoRow extends StatelessWidget {
  const _KakaoRow({required this.kakaoId});

  final String? kakaoId;

  @override
  Widget build(BuildContext context) {
    final id = kakaoId;
    return Container(
      // 세로 여백 10 은 글자 칸에만 준다 — 복사 버튼(48)은 행 높이 60 안에 세로 가운데로 들어간다.
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '카카오톡 아이디',
                    // pen 11 / 보통 굵기, 줄높이 속성 없음 · 렌더 16.
                    style: AppTypography.caption
                        .copyWith(fontSize: 11, color: AppColors.muted, height: 16 / 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // 상대가 아직 아이디를 저장하지 않았을 수 있다 — 빈 칸을 그리지 않고 말로 적는다.
                    id ?? '상대가 아직 아이디를 등록하지 않았어요',
                    // pen 16/600, 줄높이 속성 없음 · 렌더 22.
                    style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 22 / 16),
                  ),
                ],
              ),
            ),
          ),
          if (id != null)
            IconButton(
              // 누르는 영역 48, 보이는 아이콘 18 은 pen 자리(행 오른쪽 여백 12 에 붙음)에 둔다.
              padding: EdgeInsets.zero,
              alignment: Alignment.centerRight,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
