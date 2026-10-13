import 'dart:async';

import 'package:campus_mate/billing/model/billing_repository.dart';
import 'package:campus_mate/billing/model/billing_repository_provider.dart';
import 'package:campus_mate/billing/model/heart_bundles.dart';
import 'package:campus_mate/billing/model/heart_purchase_notice.dart';
import 'package:campus_mate/billing/model/heart_store_gateway.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_ui_state.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 하트 구매를 이 기기에서 여는지. 이번 범위는 안드로이드(구글 플레이)뿐이다 — iOS · 웹은 구매 영역을 숨긴다(15e-9, 계획서 7-1).
final heartPurchaseSupportedProvider = Provider<bool>((ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android);

/// 앱 수명 동안 하나(keepAlive). 로그인 뒤 관문이 열리면 앱 루트가 처음 읽어 결제 스트림 구독을 시작한다 — 상점이 닫혀 있어도
/// 늦게 온 결제를 받는다. 로그아웃하면 SessionScope 가 컨테이너째 버려 다음 사람이 앞사람의 계정 표시를 물려받지 않는다.
final heartPurchaseViewModelProvider =
    NotifierProvider<HeartPurchaseViewModel, HeartPurchaseUiState>(HeartPurchaseViewModel.new);

/// 15e · 18d 하트 구매. 결제 창 → 서버 확인 → 하트. 구매를 끝내는(소비) 것은 서버다 — 앱은 끝내지 않는다.
class HeartPurchaseViewModel extends Notifier<HeartPurchaseUiState> {
  /// 결제 결과를 하나씩 차례로 처리한다(서버 확인이 겹치지 않게).
  Future<void> _queue = Future.value();

  /// 서버로 보내는 중인 토큰 — 같은 구매가 결제 창 · 복구로 두 번 와도 한 번만 보낸다.
  final Set<String> _inFlight = {};

  /// 다시 보내도 답이 같은 토큰(다른 계정 · 이미 처리 · 확인 실패). 이 뷰모델이 사는 동안(= 이 로그인) 다시 보내지 않는다.
  final Set<String> _finished = {};

  Future<void>? _refreshing;

  HeartStoreGateway get _gateway => ref.read(heartStoreGatewayProvider);
  BillingRepository get _repository => ref.read(billingRepositoryProvider);

  @override
  HeartPurchaseUiState build() {
    if (ref.read(heartPurchaseSupportedProvider)) {
      final subscription = _gateway.events.listen(_enqueue);
      ref.onDispose(subscription.cancel);
    }
    return const HeartPurchaseUiState();
  }

  /// 앱 시작 · 상점 진입 · 복귀 때. 스토어 → 가격 · 서버 상태를 읽고 소비 안 된 지난 결제를 복구한다.
  /// [fromStore] 면 상점에 막 들어온 것이다 — 지난 배너 · 토스트 · 지급 지연을 지운다(배너 규칙: 화면을 나가면 사라짐).
  Future<void> refresh({bool fromStore = false}) {
    if (!ref.read(heartPurchaseSupportedProvider)) return Future.value();
    if (fromStore) _forgetNotices();
    return _refreshing ??= _load().whenComplete(() => _refreshing = null);
  }

  /// 상점을 새로 열었다는 것은 결제 창이 떠 있지 않다는 뜻이다 — 결제 중 · 지급 지연 표시는 풀고, 서버 확인 중만 그대로 둔다.
  /// 고른 상품도 처음(100하트)으로 — 상점을 열 때마다 pen 처럼 추천 번들이 골라져 있다.
  void _forgetNotices() {
    final phase = state.phase == HeartPurchasePhase.verifying ? HeartPurchasePhase.verifying : HeartPurchasePhase.idle;
    state = state.copyWith(banner: null, toast: null, phase: phase, selectedProductId: defaultHeartProductId);
  }

  Future<void> _load() async {
    if (!await _gateway.isAvailable()) return _markUnavailable();
    if (!ref.mounted) return;
    unawaited(_gateway.recover());
    final prices = await _loadPrices();
    final status = await _repository.fetchStatus();
    if (!ref.mounted) return;
    final loaded = status.when(onSuccess: (value) => value, onFailure: (_) => null);
    if (prices.isEmpty || loaded == null) return _markUnavailable();
    state = state.copyWith(
      availability: HeartStoreAvailability.available,
      prices: prices,
      bonus: loaded.bonus,
      accountToken: loaded.accountToken,
      banner: state.banner == HeartPurchaseNotice.unavailable ? null : state.banner,
    );
  }

  Future<Map<String, StorePrice>> _loadPrices() async {
    try {
      return await _gateway.loadPrices(heartProductIds);
    } on Exception {
      return const {};
    }
  }

  void _markUnavailable() {
    if (!ref.mounted) return;
    state = state.copyWith(availability: HeartStoreAvailability.unavailable, banner: HeartPurchaseNotice.unavailable);
  }

  void select(String productId) => state = state.copyWith(selectedProductId: productId);

  /// 고른 상품의 결제 창을 연다. 결제 중 · 확인 중에는 무시한다. 다시 구매를 시도하면 배너가 사라진다.
  Future<void> buy() async {
    final productId = state.selectedProductId;
    final accountToken = state.accountToken;
    if (!state.canBuy(productId) || accountToken == null) return;
    state = state.copyWith(phase: HeartPurchasePhase.purchasing, banner: null, toast: null);
    final opened = await _gateway.buy(productId, accountToken);
    if (opened || !ref.mounted || state.phase != HeartPurchasePhase.purchasing) return;
    _finishStoreStep(banner: HeartPurchaseNotice.failed);
    unawaited(_gateway.recover());
  }

  void clearToast() => state = state.copyWith(toast: null);

  /// 토큰은 줄에 넣는 순간 잡는다 — 차례를 기다리는 사이에 같은 구매가 복구로 또 와도 한 번만 보낸다.
  void _enqueue(List<StorePurchaseEvent> events) {
    final fresh = [
      for (final event in events)
        if (event is! StorePurchased || _claim(event.purchaseToken)) event,
    ];
    if (fresh.isEmpty) return;
    _queue = _queue.then((_) async {
      for (final event in fresh) {
        if (!ref.mounted) return;
        await _handle(event);
      }
    });
  }

  bool _claim(String token) => !_finished.contains(token) && _inFlight.add(token);

  Future<void> _handle(StorePurchaseEvent event) async {
    switch (event) {
      case StorePurchased():
        await _verify(event);
      case StorePurchasePending():
        _finishStoreStep(banner: HeartPurchaseNotice.pending);
      case StorePurchaseCanceled():
        _finishStoreStep(toast: const NoticeToast(HeartPurchaseNotice.canceled));
      case StorePurchaseFailed():
        _finishStoreStep(banner: HeartPurchaseNotice.failed);
        unawaited(_gateway.recover());
    }
  }

  /// 결제 창 단계가 끝났다 — 확인 중인 다른 결제가 없으면 다시 살 수 있다.
  void _finishStoreStep({HeartPurchaseNotice? banner, HeartPurchaseToast? toast}) {
    final phase = state.phase == HeartPurchasePhase.verifying ? state.phase : HeartPurchasePhase.idle;
    state = state.copyWith(phase: phase, banner: banner, toast: toast);
  }

  Future<void> _verify(StorePurchased purchase) async {
    final token = purchase.purchaseToken;
    state = state.copyWith(phase: HeartPurchasePhase.verifying);
    final Result<PurchaseOutcome> result;
    try {
      result = await _repository.verifyGoogle(purchase.productId, token);
    } catch (_) {
      // 저장소는 Result 로만 답하기로 했지만, 계약 밖 오류 하나가 줄(_queue)을 끊으면 이 뒤 결제가 모두 멈춘다 —
      // 지급 지연으로 두고 토큰을 풀어 다음 복구 때 다시 보낸다(돈이 걸린 길이라 넓게 잡는다).
      _inFlight.remove(token);
      if (ref.mounted) _onRejected(token, const UnknownFailure());
      return;
    }
    _inFlight.remove(token);
    if (!ref.mounted) return;
    await result.when(onSuccess: _onVerified, onFailure: (failure) async => _onRejected(token, failure));
  }

  Future<void> _onVerified(PurchaseOutcome outcome) async {
    switch (outcome) {
      case PurchasePendingAtStore():
        state = state.copyWith(phase: HeartPurchasePhase.idle, banner: HeartPurchaseNotice.pending);
      case PurchaseGranted(isNew: false):
        state = state.copyWith(phase: HeartPurchasePhase.idle, banner: null);
        ref.invalidate(myProfileProvider);
      case PurchaseGranted(:final hearts, :final bonusHearts):
        state = state.copyWith(
          phase: HeartPurchasePhase.idle,
          banner: null,
          toast: GrantedToast(hearts: hearts, bonusHearts: bonusHearts),
        );
        ref.invalidate(myProfileProvider);
        await _reloadBonus();
    }
  }

  /// 첫 구매가 끝났으면 배지가 사라져야 한다(15e-2) — 자격은 서버에 다시 묻는다.
  Future<void> _reloadBonus() async {
    final status = await _repository.fetchStatus();
    if (!ref.mounted) return;
    status.when(onSuccess: (value) => state = state.copyWith(bonus: value.bonus), onFailure: (_) {});
  }

  void _onRejected(String token, Failure failure) {
    final notice = HeartPurchaseNotice.fromVerifyFailure(failure);
    if (notice.isFinalForToken) _finished.add(token);
    final phase = notice == HeartPurchaseNotice.delayed ? HeartPurchasePhase.delayed : HeartPurchasePhase.idle;
    state = notice.isBanner
        ? state.copyWith(phase: phase, banner: notice)
        : state.copyWith(phase: phase, banner: null, toast: NoticeToast(notice));
  }
}
