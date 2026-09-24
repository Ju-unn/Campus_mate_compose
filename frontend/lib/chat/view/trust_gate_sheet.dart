import 'package:campus_mate/chat/view/chat_time.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// 신뢰 확인 시트(화면 14f, pen `p0XJA6` / 시트 `I5GLb`).
/// 매칭 24시간 뒤부터 **방에 들어올 때마다** 뜨고, 스와이프로 닫을 수 있다(강제가 아니다).
class TrustGateSheet extends StatelessWidget {
  const TrustGateSheet({
    required this.deadlineAt,
    required this.onAccept,
    required this.onLeave,
    this.myKakaoId,
    super.key,
  });

  final DateTime deadlineAt;

  /// 내가 공유하게 될 카카오톡 아이디. 서버가 방 조회에 실어 준다.
  final String? myKakaoId;

  /// 누르면 **다이얼로그 없이 바로** 수락한다 — 시트 자체가 이미 확인 절차다(pen 에 다이얼로그가 없다).
  /// 14g 미리 수락 배너는 그대로 확인을 한 번 더 받는다.
  final VoidCallback onAccept;

  /// **거절이 아니라 나가기다**(결정 11). 시트 전용 거절 경로를 만들지 않는다.
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: SafeArea(
        top: false,
        // 글자를 키운 기기에서는 시트 내용이 화면보다 길어진다 — 넘치는 만큼 스크롤한다.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '카카오톡 아이디를 공유할까요?',
                style: AppTypography.title.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '둘 다 수락하면 카카오톡 아이디와 실제 사진이 서로 공개돼요. '
                '응답 기한 안에 둘 다 수락하지 않으면 이 대화는 종료돼요.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              _Countdown(deadlineAt: deadlineAt),
              const SizedBox(height: AppSpacing.md),
              _KakaoIdBlock(myKakaoId: myKakaoId),
              const SizedBox(height: AppSpacing.md),
              AppButton(label: '수락하고 공유하기', onPressed: onAccept),
              const SizedBox(height: AppSpacing.xxs),
              // pen 라벨은 "거절하기" 였다. 거절이 곧 나가기가 되면서 라벨이 그 사실을 말해야 한다(결정 11).
              AppButton(label: '거절하고 나가기', onPressed: onLeave, variant: AppButtonVariant.text),
            ],
          ),
        ),
      ),
    );
  }
}

/// 공유할 내 카카오톡 아이디(pen `p0XJA6`). 안내 카드 자리를 대신한다 —
/// "허용을 켜 두라" 는 말은 아이디 바로 아래에 있어야 읽힌다.
///
/// [변경] 버튼은 16e-1(아이디 바꾸기) 화면이 아직 없어 붙이지 않았다 —
/// 갈 곳 없는 버튼을 그리는 대신 비워 둔다(사용자 결정 대기).
class _KakaoIdBlock extends StatelessWidget {
  const _KakaoIdBlock({required this.myKakaoId});

  /// **내** 아이디다. 상대 아이디(`ChatRoom.kakaoId`)를 여기 넘기면 게이트 전에 새어 나간다.
  final String? myKakaoId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('공유할 카카오톡 아이디', style: AppTypography.labelSmall.copyWith(color: AppColors.body)),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          // 아이디를 아직 못 받았으면 빈 칸 대신 자리만 보여준다 — 가입 때 받는 값이라 보통 있다.
          child: Text(
            myKakaoId ?? '—',
            style: AppTypography.bodyStrong.copyWith(color: AppColors.ink),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(AppIcons.circleAlert, size: 14, color: AppColors.primaryText),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                "카카오톡에서 'ID 검색 허용'이 켜져 있어야 상대가 내 아이디를 검색할 수 있어요.",
                style: AppTypography.caption.copyWith(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 응답 기한 카운트다운(pen `etT0Q`). 남은 시간은 `matches.created_at + 48시간` 에서 뺀다.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.deadlineAt});

  final DateTime deadlineAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.clock3, size: 18, color: AppColors.primaryText),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text('응답 기한까지', style: AppTypography.labelSmall.copyWith(color: AppColors.ink)),
          ),
          CountdownBuilder(
            deadlineAt: deadlineAt,
            builder: (context, remaining) => Text(
              countdownLabel(remaining),
              // pen `p0XJA6` 는 18/700 — 토큰 subtitle(17)보다 한 단계 크다.
              style: AppTypography.subtitle.copyWith(
                color: AppColors.primaryText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
