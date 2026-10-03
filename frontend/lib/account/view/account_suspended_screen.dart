import 'dart:async';

import 'package:campus_mate/account/view/withdraw_sheets.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 문의 메일. 앱에 보이라고 사용자가 정한 값이라 상수로 둔다.
const String supportEmail = 'appmailerl4538@gmail.com'; // 2026-09-26 사용자 확정

/// pen 프레임 `e7QaDh` 의 요소 사이 간격 20. 간격 토큰(md 16 · lg 24) 사이 값이다.
const double _gap = 20;

/// 정지 안내(pen `HG0d7`, 옛 `e7QaDh` 에 탈퇴하기 한 줄). 정지된 계정은 어느 화면에서든 라우터가 여기로 보낸다.
/// 앱바 · 하단 내비가 없다 — 할 수 있는 일은 로그아웃과 탈퇴(A5)뿐이다.
/// 문의 메일은 글자로만 보인다 — 메일 앱 열기(url_launcher)는 새 의존성이라 넣지 않았다.
class AccountSuspendedScreen extends ConsumerWidget {
  const AccountSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          // pen 프레임 padding [0,24,40,24].
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 40),
          child: Column(
            children: [
              // 글자를 키운 기기에서는 위쪽이 길어진다 — 로그아웃은 바닥에 두고 위만 스크롤한다.
              const Expanded(child: SingleChildScrollView(child: _SuspendedMessage())),
              const SizedBox(height: _gap),
              AppButton(label: '로그아웃', onPressed: () => unawaited(ref.read(signOutProvider)())),
              const SizedBox(height: _gap),
              // pen `r3KNbz` 312×44, 모서리 14, 14/700 muted, 밑줄 없음.
              TextButton(
                onPressed: () => showSuspendedWithdrawSheet(context),
                style: TextButton.styleFrom(
                  // 44 는 pen 의 target.compact — 기본 48 터치 여백을 붙이지 않는다.
                  minimumSize: const Size(double.infinity, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
                  foregroundColor: AppColors.muted,
                ),
                child: Text('탈퇴하기', style: AppTypography.button.copyWith(color: AppColors.muted, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 마스코트 · 제목 · 설명 · 문의 카드(pen `U7msJ` · `OYa0Y` · `FP1zb` · `JCWwK`).
class _SuspendedMessage extends StatelessWidget {
  const _SuspendedMessage();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 위 여백 사각형(`I24OnA`) 32 + 간격 20.
        const SizedBox(height: 32 + _gap),
        const Image(
          image: AssetImage('assets/images/mascot-female-sad.png'),
          width: 120,
          height: 120,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: _gap),
        Text(
          '이용이 제한된 계정이에요',
          textAlign: TextAlign.center,
          // pen 20/700, 줄높이 속성 없음 · 렌더 29.
          style: AppTypography.navTitle.copyWith(color: AppColors.ink, height: 29 / 20),
        ),
        const SizedBox(height: _gap),
        Text(
          '누적된 신고 내용을 검토한 결과, 이용이 제한되었어요. 부적절한 이용이 반복되면 계정이 삭제될 수 있어요.',
          textAlign: TextAlign.center,
          // pen 15/normal/1.5 — 15 는 글자 토큰에 없는 크기라 body 에서 크기만 바꾼다.
          style: AppTypography.body.copyWith(color: AppColors.muted, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: _gap),
        const _SupportCard(),
      ],
    );
  }
}

/// 문의 메일 카드(pen `JCWwK`). padding [14,16], 간격 8, 모서리 12, surface-soft.
class _SupportCard extends StatelessWidget {
  const _SupportCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        // 모서리 12 는 토큰 sm(8)·md(14) 사이 pen 실측값이다(NoticeCard 기본형과 같다).
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '제한 내용이 궁금하거나 잘못된 것 같다면 아래 메일로 알려 주세요.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.ink),
          ),
          const SizedBox(height: AppSpacing.xs),
          const _SupportEmailRow(),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '가입한 학교 메일 주소를 함께 적어 주시면 더 빨리 확인할 수 있어요.',
            style: AppTypography.caption.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// 문의 메일 행(pen `uDmQF`, 간격 8, 높이 22).
class _SupportEmailRow extends StatelessWidget {
  const _SupportEmailRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(AppIcons.mail, size: 20, color: AppColors.body),
        const SizedBox(width: AppSpacing.xs),
        Text('문의 메일', style: AppTypography.body.copyWith(color: AppColors.ink, fontSize: 15, height: 22 / 15)),
        const SizedBox(width: AppSpacing.xs),
        // 좁은 기기 · 큰 글자에서 주소가 넘치지 않게 남은 폭 안에서 줄을 바꾼다.
        Flexible(
          child: Text(
            supportEmail,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted, height: 22 / 14),
          ),
        ),
      ],
    );
  }
}
