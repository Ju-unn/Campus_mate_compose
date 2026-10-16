import 'dart:async';

import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_spacing.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/matching/model/card_repository.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/matching/view/profile_avatar_header.dart';
import 'package:campus_mate/matching/viewmodel/acceptance_detail_view_model.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/acceptances_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const String _title = '받은 신청';
const String _rejectLabel = '거절';
const String _acceptLabel = '수락하기';

/// 받은 신청 · 프로필 보기(pen `o4QqYR`, 사용자 결정 2026-10-16). 대화 탭 받은 신청 행의 "프로필 보기" 가 push 로 연다.
/// 상대를 10b 카드 상세와 같은 수준(아바타 · 성향 · 태그 · 소개글)으로 보고 여기서 결정한다. 실사진 · 카카오톡 아이디는
/// 신뢰 확인 뒤(14c)라 없다.
///
/// 결정은 확인 창 없이 바로 보낸다(10b 와 같은 방식). 보내기는 받은 신청 목록 뷰모델의 `respond` 를 그대로 쓴다 —
/// 연타 방지 · 성사 닉네임 · 목록 다시 읽기가 거기 있다. 성사되면 이 화면 자리에 12(매칭 성사)가 들어오고(닫으면 목록),
/// 성사가 아니거나 거절이면 목록으로 돌아간다. 보내기가 실패하면 10b 처럼 이 화면에 남아 문구를 보인다.
class AcceptanceDetailScreen extends ConsumerStatefulWidget {
  const AcceptanceDetailScreen({required this.cardId, super.key});

  final String cardId;

  @override
  ConsumerState<AcceptanceDetailScreen> createState() => _AcceptanceDetailScreenState();
}

class _AcceptanceDetailScreenState extends ConsumerState<AcceptanceDetailScreen> {
  /// 이 화면에서 결정을 보냈다. 목록 상태의 오류 문구는 목록 읽기 실패일 수도 있어, 보낸 뒤의 문구만 이 화면의 실패로 본다.
  var _sent = false;

  @override
  Widget build(BuildContext context) {
    final cardId = widget.cardId;
    final state = ref.watch(acceptanceDetailViewModelProvider(cardId));
    final acceptances = ref.watch(acceptancesViewModelProvider);
    // 이 카드의 답이 끝난 순간(보내는 중 → 끝) 한 번만 본다. 목록 다시 읽기는 respond 가 이어서 한다.
    ref.listen(acceptancesViewModelProvider, (previous, next) {
      if (previous?.respondingCardId == cardId && next.respondingCardId == null) {
        _afterResponse(next);
      }
    });

    final detail = state.detail;
    final busy = acceptances.respondingCardId != null;
    return Scaffold(
      // pen `WpvDL` 와 같은 앱바(14c) — 8 + 48 에 titleSpacing 4 로 화살표 가운데 x32, 제목 x60.
      appBar: AppBar(
        leadingWidth: 56,
        titleSpacing: 4,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: BackButton(color: AppColors.ink, onPressed: _leave),
        ),
        title: Text(_title, style: AppTypography.navTitle),
      ),
      bottomNavigationBar: detail == null
          ? null
          : _DecisionBar(
              errorMessage: _sent ? acceptances.errorMessage : null,
              onReject: busy ? null : () => _respond(CardDecision.reject),
              onAccept: busy ? null : () => _respond(CardDecision.accept),
            ),
      body: SafeArea(
        child: switch (detail) {
          // 읽기 실패(404 · 409 · 410 · 연결)는 pen 에 없는 상태다 — 10b 와 같은 가운데 회색 문구.
          null when state.errorMessage != null => DetailMessage(text: state.errorMessage!),
          null => const Center(child: CircularProgressIndicator()),
          _ => SingleChildScrollView(
            // 카드가 앱바에 바로 붙는다(10b `TORAs` 와 같은 본문 여백).
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            child: ProfileCard(detail: detail, header: ProfileAvatarHeader(url: detail.profile.avatarUrl)),
          ),
        },
      ),
    );
  }

  void _respond(CardDecision decision) {
    setState(() => _sent = true);
    unawaited(ref.read(acceptancesViewModelProvider.notifier).respond(widget.cardId, decision));
  }

  /// 성사 → 이 화면 자리에 12. 실패 → 남는다(문구는 바가 보인다). 그 밖(거절 · 성사 아닌 수락) → 목록으로.
  void _afterResponse(AcceptancesUiState next) {
    final nickname = next.matchedNickname;
    if (nickname != null) {
      ref.read(acceptancesViewModelProvider.notifier).consumeMatched();
      context.pushReplacement(AppRoutes.matchMade, extra: (nickname: nickname, matchId: next.matchedMatchId));
      return;
    }
    if (next.errorMessage == null) {
      _leave();
    }
  }

  /// 행에서 push 로 열린다. 스택이 한 장뿐이면(링크로 바로 열림) pop 할 곳이 없어 대화 탭으로 간다(14c 와 같다).
  void _leave() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    GoRouter.maybeOf(context)?.go(AppRoutes.conversations);
  }
}

/// 하단 고정 바(pen `o4QqYR`, DESIGN §8.2 "화면 하단 고정 · 세이프 에어리어 위 · canvas 바탕 · 위 hairline 1px").
/// 거절 폭 104 · 수락하기 남은 폭, 사이 12, 높이 56 — 10b [CardActionBar] 와 같은 짜임에 거절은 secondary 색이다.
/// 글자를 키우면 두 버튼이 같은 높이로 함께 커진다.
class _DecisionBar extends StatelessWidget {
  const _DecisionBar({required this.onReject, required this.onAccept, this.errorMessage});

  final VoidCallback? onReject;
  final VoidCallback? onAccept;

  /// 보내기 실패 문구(pen 에 없는 상태 — 10b 처럼 버튼 곁에 빨간 작은 글씨).
  final String? errorMessage;

  /// 거절 버튼 폭(pen `o4QqYR`, 10b 와 같은 값).
  static const double _rejectWidth = 104;

  @override
  Widget build(BuildContext context) {
    final message = errorMessage;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null) ...[
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _rejectWidth,
                      child: _DecisionButton(
                        icon: AppIcons.x,
                        label: _rejectLabel,
                        background: AppColors.primaryDisabled,
                        foreground: AppColors.ink,
                        iconGap: 6,
                        onPressed: onReject,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _DecisionButton(
                        icon: AppIcons.check,
                        label: _acceptLabel,
                        background: AppColors.primary,
                        foreground: AppColors.onPrimary,
                        iconGap: AppSpacing.xs,
                        onPressed: onAccept,
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

/// 아이콘 + 글자 버튼. [AppButton] 은 앞 아이콘이 없어 10b [CardActionBar] 의 버튼 모양(모서리 8 · 아이콘 20 · 18/700)을 따른다.
/// 낭독기는 글자 하나를 버튼 이름으로 읽는다(아이콘에는 이름이 없다).
class _DecisionButton extends StatelessWidget {
  const _DecisionButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.iconGap,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final double iconGap;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: AppColors.primaryDisabled,
        disabledForegroundColor: AppColors.disabled,
        elevation: 0,
        // 높이는 최소 56 이고 글자가 커지면 따라 커진다 — 고정하면 두 줄 글자가 조용히 잘린다.
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        minimumSize: const Size(0, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          SizedBox(width: iconGap),
          Flexible(child: Text(label, textAlign: TextAlign.center, style: AppTypography.label)),
        ],
      ),
    );
  }
}
