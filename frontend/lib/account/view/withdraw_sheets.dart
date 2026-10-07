import 'dart:async';

import 'package:campus_mate/account/viewmodel/withdraw_view_model.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/viewmodel/notification_settings_view_model.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 16c 탈퇴 확인(DESIGN §9 · `account-delete-sheet`). 설정 위에 뜨는 바텀시트 둘 — 1차(pen `t4KbA`)에서
/// "영구 삭제"를 고르면 최종(pen `s7M9MC`)이 뜬다. 딤 · 키보드 밀기는 조각 6 시트와 같은 [showSafetySheet] 를 쓴다.
Future<void> showWithdrawSheets(BuildContext context) async {
  final wantsDelete = await showSafetySheet<bool>(context, (_) => const WithdrawFirstSheet());
  if (wantsDelete != true || !context.mounted) {
    return;
  }
  await showSafetySheet<void>(context, (_) => const WithdrawFinalSheet());
}

/// 14f-1 정지 중 탈퇴(pen `XHGTs`). 정지 중엔 일시중지가 뜻이 없어 1차 시트 없이 최종 시트 한 장이다(A5 · 대장 10-03).
Future<void> showSuspendedWithdrawSheet(BuildContext context) =>
    showSafetySheet<void>(context, (_) => const WithdrawFinalSheet.suspended());

/// 1차 시트(pen `t4KbA`). 탈퇴보다 먼저 매칭 일시중지를 권한다(설계 §2.6 — 재가입 2개월 제한).
class WithdrawFirstSheet extends ConsumerWidget {
  const WithdrawFirstSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _WithdrawSheetFrame(
      gap: 14,
      children: [
        const _FirstSheetHeader(),
        _PauseOffer(
          // Ruling 33 — 설정의 "매칭 활성화" 토글과 같은 상태다. 닫으면 그 토글이 꺼진 모습으로 결과를 보여 준다.
          onPause: () {
            unawaited(ref.read(notificationSettingsViewModelProvider.notifier).setPaused(true));
            Navigator.of(context).pop();
          },
        ),
        Text('탈퇴하면 아래 내용이 삭제돼요', style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 1.5)),
        const _DeletedItems(),
        Text(
          '삭제한 내용은 되돌릴 수 없고, 재가입은 2개월 뒤에 가능해요.',
          style: AppTypography.labelSmall.copyWith(color: AppColors.error, height: 1.5),
        ),
        // pen: 경고 글 끝(y 460)과 버튼(y 522) 사이 62 = 간격 14 + 34 + 14.
        const SizedBox(height: 34),
        AppButton(
          label: '영구 삭제',
          variant: AppButtonVariant.neutral, // pen 회색 `l1XDPi`(사용자 요청 2026-10-08 — 노드 `l44zcf` 와 같게)
          onPressed: () => Navigator.of(context).pop(true),
        ),
        _CancelButton(onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
  }
}

/// 최종 시트(pen `s7M9MC`). "정말 영구 삭제" 한 번이 곧 탈퇴다.
/// [WithdrawFinalSheet.suspended] 는 제목 · 경고만 다른 14f-1(pen `XHGTs`)이다 — 본문 · 버튼은 같은 위험 무게로 둔다(대장 10-03).
class WithdrawFinalSheet extends ConsumerWidget {
  const WithdrawFinalSheet({super.key})
      : _title = '정말 삭제할까요?',
        _warning = '재가입은 탈퇴 후 2개월이 지나야 가능해요.';

  /// 정지 중 탈퇴는 재가입 제한이 무기한이다(서버 `withdraw_account`).
  const WithdrawFinalSheet.suspended({super.key})
      : _title = '정지 중에 탈퇴할까요?',
        _warning = '정지 중에 탈퇴하면 다시 가입할 수 없어요';

  final String _title;
  final String _warning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(withdrawViewModelProvider);
    return _WithdrawSheetFrame(
      gap: AppSpacing.md,
      children: [
        Text(_title, style: AppTypography.headline.copyWith(color: AppColors.ink, height: 1.5)),
        Text(
          '프로필, 매칭 기록, 대화를 모두 영구적으로 삭제합니다. 이 작업은 취소할 수 없어요.',
          style: AppTypography.body.copyWith(color: AppColors.body, height: 1.5),
        ),
        _RejoinWarning(_warning),
        // pen 에 없는 상태 — 탈퇴하지 못했을 때만 한 줄.
        if (state.errorMessage != null)
          Text(state.errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.error)),
        // pen: 배지 끝(y 201)과 버튼(y 286) 사이 85 = 간격 16 + 53 + 16.
        const SizedBox(height: 53),
        AppButton(
          label: '정말 영구 삭제',
          variant: AppButtonVariant.neutral, // pen 회색 `FbrhB`
          onPressed: state.isSubmitting ? null : ref.read(withdrawViewModelProvider.notifier).withdraw,
        ),
        _CancelButton(onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

/// 16c 두 시트의 틀. padding [12,16,24,16], 위 모서리 24, 손잡이 36×4 — 조각 6 [SafetySheet] 와 여백이 달라 따로 둔다.
class _WithdrawSheetFrame extends StatelessWidget {
  const _WithdrawSheetFrame({required this.gap, required this.children});

  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        // 글자를 키운 기기에서는 시트가 화면보다 길어진다 — 넘치는 만큼 스크롤한다.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gap,
            children: [const Center(child: SheetHandle()), ...children],
          ),
        ),
      ),
    );
  }
}

/// 마스코트 88(pen `ycFq3`) 옆에 제목 · 부제. 머리 묶음 높이 112 안에서 마스코트가 y 12 에 놓인다.
class _FirstSheetHeader extends StatelessWidget {
  const _FirstSheetHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Image(
            image: AssetImage('assets/images/mascot-female-sad.png'),
            width: 88,
            height: 88,
            fit: BoxFit.contain, // pen `x3aGgV` 88×88 contain
            excludeFromSemantics: true,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('정말 떠나시나요?', style: AppTypography.headline.copyWith(color: AppColors.ink, height: 1.5)),
                Text(
                  '탈퇴보다 먼저 매칭을 잠시 쉬어볼 수 있어요.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.body, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "매칭만 잠시 멈추기" 행(pen `Z6Es4`). padding 14, 간격 12, 모서리 14, primary-wash.
class _PauseOffer extends StatelessWidget {
  const _PauseOffer({required this.onPause});

  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('매칭만 잠시 멈추기', style: AppTypography.bodyStrong.copyWith(color: AppColors.ink, height: 1.5)),
                Text(
                  '프로필과 대화는 그대로 유지돼요.',
                  style: AppTypography.caption.copyWith(color: AppColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // pen `YxeET` 76×48, 투명, 모서리 8, 좌우 12. TextButton 은 자기 Material 에 잉크를 그려 시트와 같이 움직인다(COMMON §4-2).
          TextButton(
            onPressed: onPause,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              foregroundColor: AppColors.primaryText,
            ),
            child: Text('일시중지', style: AppTypography.labelSmall.copyWith(color: AppColors.primaryText, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

/// 삭제되는 항목(pen `J8iid`). padding [4,14], 모서리 14, surface-soft, 줄 높이 44((140 − 8) ÷ 3).
class _DeletedItems extends StatelessWidget {
  const _DeletedItems();

  /// pen 줄의 3D 아이콘 인스턴스 `PkqpC`(프로필) · `zxXQG`(하트) · `Lua1H`(대화).
  static const _items = <(AppIcon3d, String)>[
    (AppIcon3d.userRound, '프로필과 인증 정보'),
    (AppIcon3d.heart, '수락 매칭 기록'),
    (AppIcon3d.chat, '모든 대화 내용'),
  ];

  /// pen 은 인스턴스 크기를 20~24 로 두었다 — 줄 높이 44 안에서 가운데 값.
  static const double _iconSize = 22;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          for (final (icon, label) in _items)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Icon3d(icon, size: _iconSize),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.body, height: 1.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 재가입 안내 배지(pen `x36KQ`). padding 14, 간격 10, 모서리 14. 채움은 errorWash(#FAEFEC, 대장 결정 1 —
/// pen 은 #FFF3F0 이었고 묶음 5 에서 #FAEFEC 로 고쳤다. 글자 #C13515 대비 4.9).
class _RejoinWarning extends StatelessWidget {
  const _RejoinWarning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.alertTriangle, size: 20, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.labelSmall.copyWith(color: AppColors.error, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 16c 취소 버튼(pen `fEu75` · `dNi02`). 328×48, 모서리 14, #FF385C, 글자 흰색 16/700 — AppButton(52)과 높이가 달라 여기 둔다.
class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      // 눌림 효과가 시트와 같이 움직이게 버튼 안에 Material 을 둔다(COMMON §4-2).
      child: Material(
        color: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          // 높이는 최소값만 건다 — 글자를 키우면 버튼이 따라 커진다.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(child: Text('취소', style: AppTypography.bodyStrong.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700))),
          ),
        ),
      ),
    );
  }
}
