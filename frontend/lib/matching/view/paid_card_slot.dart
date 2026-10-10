import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/matching/model/paid_card.dart';
import 'package:campus_mate/matching/view/paid_card_info_sheet.dart';
import 'package:campus_mate/matching/view/paid_card_locked.dart';
import 'package:campus_mate/matching/view/paid_card_purchase_sheets.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_ui_state.dart';
import 'package:campus_mate/matching/viewmodel/today_cards_view_model.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 오늘 탭의 결제 카드 자리(pen `b2jvOY` · 0명 `IJGRA`). 무엇을 그릴지는 [paidCard] 가 정하고,
/// 눌렀을 때의 흐름(확인 시트 → 열기)은 여기서 묶는다. 화면 파일이 커지지 않게 따로 뒀다.
class PaidCardSlot extends ConsumerStatefulWidget {
  const PaidCardSlot({required this.paidCard, super.key});

  final PaidCard paidCard;

  @override
  ConsumerState<PaidCardSlot> createState() => _PaidCardSlotState();
}

class _PaidCardSlotState extends ConsumerState<PaidCardSlot> {
  /// 잔액을 읽고 확인 시트를 띄우는 동안 true — 그 사이 다시 눌러도 시트가 겹쳐 뜨지 않게 버튼을 잠근다.
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    return switch (widget.paidCard) {
      PaidCardOffered offered => PaidCardLocked(
          card: offered,
          busy: _opening || ref.watch(todayCardsViewModelProvider.select((state) => state.isPurchasing)),
          onInfo: () => showPaidCardInfoSheet(context),
          onOpen: () => _open(offered),
        ),
      PaidCardEmpty() => const PaidCardEmptyNotice(),
    };
  }

  /// "N으로 열기" → (잔액을 서버에서 새로 읽음) → 확인 시트 → 열기. 취소하면 아무 일도 없다.
  /// 새로 읽은 잔액이 모자라면 확인 시트를 건너뛰고 바로 "하트가 모자라요" 시트다(눌러 봐야 서버 402 일 일이라).
  /// 잔액을 못 읽으면(null) 부족 판정은 서버 402 에 맡기고 잔액 문장 없이 확인 시트를 띄운다.
  Future<void> _open(PaidCardOffered offered) async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    try {
      final balance = await _heartBalance(ref);
      if (!mounted) {
        return;
      }
      if (balance != null && balance < offered.cost) {
        await _offerHeartStore(context, ref, cost: offered.cost, balance: balance);
        return;
      }
      final confirmed = await showPaidCardConfirmSheet(context, cost: offered.cost, heartBalance: balance);
      if (!confirmed || !mounted) {
        return;
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
    await ref.read(todayCardsViewModelProvider.notifier).purchase(offered.offerId);
  }
}

/// 열다가 생긴 일을 화면에 한 번 알린다(오늘 탭이 `ref.listen` 으로 부른다).
/// 결제 카드가 사라지는 409 에서도 알림이 남도록 카드 자리가 아니라 화면 쪽에서 듣는다.
Future<void> handlePurchaseNotice(BuildContext context, WidgetRef ref, PurchaseNotice notice) async {
  final viewModel = ref.read(todayCardsViewModelProvider.notifier);
  final paid = ref.read(todayCardsViewModelProvider).paidCard;
  viewModel.consumeNotice();
  if (notice.kind != PurchaseNoticeKind.heartsNotEnough) {
    showPollToast(context, notice.message ?? paidOfferGoneMessage);
    return;
  }
  if (paid is! PaidCardOffered) {
    showPollToast(context, heartsNotEnoughMessage);
    return;
  }
  final balance = await _heartBalance(ref);
  if (!context.mounted) {
    return;
  }
  await _offerHeartStore(context, ref, cost: paid.cost, balance: balance);
}

/// "하트가 모자라요" 시트 → "하트 스토어로 가기" 면 스토어를 열고, 돌아오면 잔액을 다시 읽게 한다.
Future<void> _offerHeartStore(BuildContext context, WidgetRef ref, {required int cost, required int? balance}) async {
  final toStore = await showPaidCardHeartsShortSheet(context, cost: cost, heartBalance: balance);
  if (!toStore || !context.mounted) {
    return;
  }
  await context.push<void>(AppRoutes.heartStore);
  // 스토어에서 하트를 채웠을 수 있다 — 잔액을 무효로 해 다음에 읽을 때 새로 가져온다.
  if (context.mounted) {
    ref.invalidate(myProfileProvider);
  }
}

/// 내 하트 잔액을 **서버에서 새로** 읽는다. 내 정보 provider 는 한 번 읽으면 캐시되어 서버가 하트를 지급한 뒤에도
/// 옛 값을 보여 줬다 — 무효로 만든 뒤 다시 읽는다(새 API 없이 기존 provider 의 무효화 관례를 따른다).
/// 읽기 실패이면 null — 시트가 잔액 문장을 뺀다.
Future<int?> _heartBalance(WidgetRef ref) async {
  ref.invalidate(myProfileProvider);
  final result = await ref.read(myProfileProvider.future);
  return result.when(onSuccess: (profile) => profile.heartBalance, onFailure: (_) => null);
}
