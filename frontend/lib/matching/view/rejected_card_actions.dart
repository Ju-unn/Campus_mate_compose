import 'dart:async';

import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_snack_bar.dart';
import 'package:campus_mate/common/widgets/confirm_popup.dart';
import 'package:campus_mate/core/l10n/error_text.dart';
import 'package:campus_mate/core/l10n/l10n_context.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/data/acceptance.dart';
import 'package:campus_mate/matching/model/data/rejected_card.dart';
import 'package:campus_mate/matching/viewmodel/rejected_cards_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 거절한 카드의 두 일(1.0.7 #20) — 대화 탭 [거절한 카드] 줄과 거절한 카드 · 프로필 보기(pen hhlWE)가 같이 쓴다.

/// [다시 신청하기] — 확인 팝업(pen Co9Bw, 공용 v14xI) → 다시 신청. 보내는 동안 팝업의 [신청하기] 가 돈다.
/// 보냈으면 참, 못 보냈으면 거짓, [취소] 면 null(남아 있던 옛 오류를 다시 띄우지 않게).
/// 실패 문구는 뷰모델 오류 칸에 남는다(부른 쪽이 그린다).
Future<bool?> confirmAndReapply(BuildContext context, WidgetRef ref, String cardId) async {
  final l10n = context.l10n;
  final viewModel = ref.read(rejectedCardsViewModelProvider.notifier);
  bool? sent;
  await showConfirmPopup(
    context,
    title: l10n.matchingRejectedReapplyConfirmTitle,
    body: l10n.matchingRejectedReapplyConfirmBody,
    confirmLabel: l10n.matchingRejectedReapplyConfirm,
    onConfirm: () async => sent = await viewModel.reapply(cardId),
  );
  return sent;
}

/// [수락하기](받은 신청에 한 거절 되돌리기) — 매칭되면 매칭 화면(12)으로 보낼 값.
/// 확인 팝업 없이 바로 보낸다(사용자 결정 「받은 신청 되돌리기 = 바로 매칭」, 대장 확정 11-24).
Future<MatchMadeArgs?> undoRejection(BuildContext context, WidgetRef ref, String cardId) =>
    ref.read(rejectedCardsViewModelProvider.notifier).undo(cardId);

/// 거절한 카드 · 프로필 보기의 아래 버튼(pen hhlWE DJ46i: 폭 꽉 · 56 · primary · 모서리 8 · heart 20 + 8 + 18/700).
/// AppButton 작은 크기(모서리 8 · 18/700)에 높이만 56 이다(대장 판정 6).
/// 받은 신청을 거절한 줄은 같은 자리에 [수락하기](사용자 선택, 대장 확정 11-24 — 받은 신청 수락과 같은 체크 아이콘).
/// 다시 신청을 보내면 참을 들고 목록으로 돌아간다(목록이 [보낸 신청] 탭 · 토스트로 안내). 매칭되면 이 화면 자리에 12.
class RejectedProfileAction extends ConsumerWidget {
  const RejectedProfileAction({required this.cardId, required this.source, super.key});

  final String cardId;
  final RejectedSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final submitting = ref.watch(rejectedCardsViewModelProvider.select((state) => state.submittingCardId));
    final reapply = source == RejectedSource.card;
    return AppButton(
      label: reapply ? context.l10n.matchingRejectedReapply : context.l10n.matchingAcceptanceDetailAccept,
      size: AppButtonSize.small,
      height: 56,
      leading: Icon(reapply ? AppIcons.heart : AppIcons.check, size: 20),
      isLoading: !reapply && submitting == cardId,
      onPressed: submitting != null ? null : () => unawaited(reapply ? _reapply(context, ref) : _undo(context, ref)),
    );
  }

  Future<void> _reapply(BuildContext context, WidgetRef ref) async {
    final sent = await confirmAndReapply(context, ref, cardId);
    if (!context.mounted || sent == null) return;
    if (!sent) {
      _showFailure(context, ref);
      return;
    }
    _leave(context, sent: true);
  }

  Future<void> _undo(BuildContext context, WidgetRef ref) async {
    final matched = await undoRejection(context, ref, cardId);
    if (!context.mounted) return;
    if (matched == null) {
      _showFailure(context, ref);
      return;
    }
    // 받은 신청 · 프로필 보기의 수락과 같은 길 — 이 화면 자리에 12, 닫으면 목록.
    context.pushReplacement(AppRoutes.matchMade, extra: matched);
  }

  /// 이 화면에는 목록의 오류 줄이 없어 실패 문구를 스낵바로 보인다(pen 에 없는 상태 — 대장 판정 9).
  void _showFailure(BuildContext context, WidgetRef ref) {
    final error = ref.read(rejectedCardsViewModelProvider).error;
    if (error == null) return;
    showAppSnackBar(ScaffoldMessenger.of(context), SnackBar(content: Text(context.errorText(error))));
  }

  /// 목록에서 push 로 열린다. 스택이 한 장뿐이면(링크로 바로 열림) 대화 탭으로 간다.
  void _leave(BuildContext context, {required bool sent}) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) return navigator.pop(sent);
    GoRouter.maybeOf(context)?.go(AppRoutes.conversations);
  }
}
