import 'dart:async';

import 'package:campus_mate/billing/model/billing_repository.dart';
import 'package:campus_mate/billing/model/billing_repository_provider.dart';
import 'package:campus_mate/billing/model/heart_purchase_notice.dart';
import 'package:campus_mate/billing/model/heart_store_gateway.dart';
import 'package:campus_mate/billing/model/payment_store.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_ui_state.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../me/model/fake_me_repository.dart';
import '../model/fake_billing_repository.dart';
import '../model/fake_heart_store_gateway.dart';

void main() {
  late FakeHeartStoreGateway gateway;
  late FakeBillingRepository repo;
  late FakeMeRepository me;
  late ProviderContainer container;

  ProviderContainer makeContainer({bool supported = true, PaymentStore store = PaymentStore.googlePlay}) {
    final made = ProviderContainer(overrides: [
      heartStoreGatewayProvider.overrideWithValue(gateway),
      billingRepositoryProvider.overrideWithValue(repo),
      heartPurchaseSupportedProvider.overrideWithValue(supported),
      paymentStoreProvider.overrideWithValue(store),
      meRepositoryProvider.overrideWithValue(me),
    ]);
    addTearDown(made.dispose);
    return made;
  }

  setUp(() {
    gateway = FakeHeartStoreGateway();
    repo = FakeBillingRepository();
    me = FakeMeRepository(const FailureResult(NetworkFailure()));
    container = makeContainer();
  });

  HeartPurchaseViewModel vm() => container.read(heartPurchaseViewModelProvider.notifier);
  HeartPurchaseUiState state() => container.read(heartPurchaseViewModelProvider);

  /// 상점을 연 것처럼 — 가격 · 자격 · 계정 표시를 읽고 복구까지.
  Future<void> openStore() async {
    await vm().refresh(fromStore: true);
    await pumpEventQueue();
  }

  Future<void> emit(List<StorePurchaseEvent> events) async {
    gateway.emit(events);
    await pumpEventQueue();
  }

  group('불러오기(refresh)', () {
    test('스토어를 쓸 수 있으면 가격 · 첫 구매 자격 · 계정 표시를 읽고, 소비 안 된 지난 결제를 복구한다', () async {
      await openStore();

      final s = state();
      expect(s.availability, HeartStoreAvailability.available);
      expect((s.accountToken, s.bonus?.hearts, s.prices.length), (fakeAccountToken, 50, 5));
      expect((gateway.recoverCount, repo.statusCount), (1, 1));
      expect(s.canBuy('heart_100'), isTrue);
    });

    test('스토어를 쓸 수 없으면(15e-7) 결제 불가 배너 · 구매 막힘, 서버 · 복구는 부르지 않는다', () async {
      gateway.available = false;

      await openStore();

      expect((state().availability, state().banner), (HeartStoreAvailability.unavailable, HeartPurchaseNotice.unavailable));
      expect(state().canBuy('heart_100'), isFalse);
      expect((gateway.recoverCount, repo.statusCount), (0, 0));
    });

    test('스토어가 가격을 하나도 안 주면 결제 불가(15e-8 "가격 0개")', () async {
      gateway.prices = {};

      await openStore();

      expect((state().availability, state().banner), (HeartStoreAvailability.unavailable, HeartPurchaseNotice.unavailable));
    });

    test('서버 상태(/billing/status)를 못 읽으면 계정 표시가 없어 사지 못한다 — 결제 불가 배너(pen 에 없는 상태)', () async {
      repo.status = const FailureResult(NetworkFailure());

      await openStore();

      expect((state().availability, state().banner), (HeartStoreAvailability.unavailable, HeartPurchaseNotice.unavailable));
      expect(gateway.recoverCount, 1, reason: '복구는 계정 표시 없이도 된다 — 서버가 계정을 대조한다');
    });

    test('가격을 못 읽은 상품만 못 산다', () async {
      gateway.prices = Map.of(storePricesWon())..remove('heart_800');

      await openStore();

      expect((state().canBuy('heart_100'), state().canBuy('heart_800')), (true, false));
    });

    test('구매를 열지 않는 기기(웹 · 데스크톱)면 아무것도 부르지 않는다', () async {
      container = makeContainer(supported: false);

      await openStore();
      gateway.emit([const StorePurchased('heart_100', 'tok')]);
      await pumpEventQueue();

      expect((gateway.availableCount, gateway.recoverCount, repo.statusCount, repo.verified.length), (0, 0, 0, 0));
      expect(state().canBuy('heart_100'), isFalse);
    });

    test('상점에 들어오면 지난 배너 · 토스트 · 지급 지연을 지운다(배너 규칙: 화면을 나가면 사라짐)', () async {
      await openStore();
      repo.outcome = const FailureResult(ServerUnavailableFailure());
      await emit([const StorePurchased('heart_100', 'tok')]);
      expect((state().phase, state().banner), (HeartPurchasePhase.delayed, HeartPurchaseNotice.delayed));
      repo.outcome = const Success(PurchaseGranted(hearts: 100, bonusHearts: 0, isNew: true));
      gateway.unconsumed = const [StorePurchased('heart_100', 'tok')];

      await openStore();

      expect(state().banner, isNull);
      expect(state().phase, HeartPurchasePhase.idle);
      expect((state().toast! as GrantedToast).message, '100하트가 들어왔어요', reason: '다시 열면 이어서 들어온다');
    });

    test('결제 창 결과가 끝내 안 온 채 상점을 다시 열면 결제 중 표시를 풀어 다시 살 수 있다(확인 중은 그대로)', () async {
      await openStore();
      await vm().buy();
      expect(state().phase, HeartPurchasePhase.purchasing);

      await openStore();

      expect(state().phase, HeartPurchasePhase.idle);
      repo.holdVerify = Completer<void>();
      gateway.emit([const StorePurchased('heart_100', 'tok')]);
      await pumpEventQueue();
      await openStore();
      expect(state().phase, HeartPurchasePhase.verifying);
      repo.holdVerify!.complete();
    });

    test('상점에 다시 들어오면 고른 상품은 처음처럼 100하트(pen `J0o8uB`), 복귀 때는 그대로', () async {
      await openStore();
      vm().select('heart_800');

      await vm().refresh();
      expect(state().selectedProductId, 'heart_800');
      await openStore();

      expect(state().selectedProductId, 'heart_100');
    });

    test('복귀 때(fromStore 아님)는 보이던 배너를 지우지 않는다', () async {
      await openStore();
      await emit([const StorePurchaseFailed('')]);

      await vm().refresh();
      await pumpEventQueue();

      expect(state().banner, HeartPurchaseNotice.failed);
    });
  });

  group('구매(buy)', () {
    test('고른 상품을 계정 표시와 함께 결제 창으로 — 결제 창 대기(18d-3) 동안 진행 단계는 purchasing', () async {
      await openStore();
      vm().select('heart_200');

      await vm().buy();

      expect(gateway.bought, [('heart_200', fakeAccountToken)]);
      expect(state().phase, HeartPurchasePhase.purchasing);
      expect(state().canBuy('heart_200'), isFalse);
    });

    test('결제 중에 또 누르면 무시한다(결제 창은 한 번)', () async {
      await openStore();

      await vm().buy();
      await vm().buy();

      expect(gateway.bought, hasLength(1));
    });

    test('다시 구매를 시도하면 배너가 사라진다', () async {
      await openStore();
      await emit([const StorePurchaseFailed('')]);
      expect(state().banner, HeartPurchaseNotice.failed);

      await vm().buy();

      expect(state().banner, isNull);
    });

    test('결제 창을 못 열면 결제 실패 배너 + 지난 결제 복구', () async {
      await openStore();
      gateway.opens = false;
      final recovered = gateway.recoverCount;

      await vm().buy();
      await pumpEventQueue();

      expect((state().phase, state().banner), (HeartPurchasePhase.idle, HeartPurchaseNotice.failed));
      expect(gateway.recoverCount, recovered + 1);
    });

    test('불러오기 전에는 사지 않는다', () async {
      await vm().buy();

      expect(gateway.bought, isEmpty);
    });
  });

  group('결제 창 결과', () {
    setUp(() async {
      await openStore();
      await vm().buy();
    });

    test('취소 → "결제를 취소했어요" 토스트, 다시 살 수 있다', () async {
      await emit([const StorePurchaseCanceled('')]);

      expect((state().toast! as NoticeToast).notice, HeartPurchaseNotice.canceled);
      expect((state().phase, state().banner), (HeartPurchasePhase.idle, null));
      expect(repo.verified, isEmpty);
    });

    test('대기(pending) → "결제 확인을 기다리고 있어요" 배너, 서버는 부르지 않는다', () async {
      await emit([const StorePurchasePending('heart_100')]);

      expect((state().phase, state().banner), (HeartPurchasePhase.idle, HeartPurchaseNotice.pending));
      expect(repo.verified, isEmpty);
    });

    test('실패(error) → 결제 실패 배너 + 지난 결제 복구', () async {
      final recovered = gateway.recoverCount;

      await emit([const StorePurchaseFailed('')]);

      expect((state().phase, state().banner), (HeartPurchasePhase.idle, HeartPurchaseNotice.failed));
      expect(gateway.recoverCount, recovered + 1);
    });

    test('결제됨 → 서버 확인 중(15e-3)에는 verifying', () async {
      repo.holdVerify = Completer<void>();

      await emit([const StorePurchased('heart_100', 'tok')]);

      expect(state().phase, HeartPurchasePhase.verifying);
      expect(repo.verified, [('heart_100', 'tok')]);
      repo.holdVerify!.complete();
      await pumpEventQueue();
      expect(state().phase, HeartPurchasePhase.idle);
    });

    test('첫 구매 성공(15e-4) → "150하트가 들어왔어요(보너스 50 포함)", 잔액 · 자격을 다시 읽는다', () async {
      container.listen(myProfileProvider, (_, _) {});
      await pumpEventQueue();
      final profileReads = me.calls;
      final statusReads = repo.statusCount;
      repo.status = Success(BillingStatus(accountToken: fakeAccountToken));

      await emit([const StorePurchased('heart_100', 'tok')]);

      expect((state().toast! as GrantedToast).message, '150하트가 들어왔어요(보너스 50 포함)');
      expect(me.calls, profileReads + 1, reason: '하트 잔액 provider 를 새로 읽는다');
      expect(repo.statusCount, statusReads + 1);
      expect(state().bonus, isNull, reason: '구매 뒤에는 배지가 사라진다(15e-2)');
    });

    test('보너스 없는 성공(15e-5) → "100하트가 들어왔어요"', () async {
      repo.outcome = const Success(PurchaseGranted(hearts: 100, bonusHearts: 0, isNew: true));

      await emit([const StorePurchased('heart_100', 'tok')]);

      expect((state().toast! as GrantedToast).message, '100하트가 들어왔어요');
    });

    test('확인 시트에서 보너스를 봤어도 서버가 0 을 주면 실제 지급만 말한다', () async {
      expect(state().bonus!.appliesTo(100), isTrue);
      repo.outcome = const Success(PurchaseGranted(hearts: 100, bonusHearts: 0, isNew: true));

      await emit([const StorePurchased('heart_100', 'tok')]);

      expect((state().toast! as GrantedToast).message, '100하트가 들어왔어요');
      expect(repo.verified, [('heart_100', 'tok')]);
    });

    test('이미 받은 결제(already_granted)는 안내 없이 잔액만 다시 읽는다', () async {
      container.listen(myProfileProvider, (_, _) {});
      await pumpEventQueue();
      final profileReads = me.calls;
      repo.outcome = const Success(PurchaseGranted(hearts: 100, bonusHearts: 0, isNew: false));

      await emit([const StorePurchased('heart_100', 'tok')]);

      expect((state().toast, state().banner, state().phase), (null, null, HeartPurchasePhase.idle));
      expect(me.calls, profileReads + 1);
    });

    test('서버 202 → 대기 배너', () async {
      repo.outcome = const Success(PurchasePendingAtStore());

      await emit([const StorePurchased('heart_100', 'tok')]);

      expect((state().phase, state().banner), (HeartPurchasePhase.idle, HeartPurchaseNotice.pending));
    });

    for (final failure in const <Failure>[ServerUnavailableFailure(), NetworkFailure()]) {
      test('${failure.runtimeType} → 지급 지연(15e-6) · 구매를 끝내지 않아 다음 복구 때 다시 보낸다', () async {
        repo.outcome = FailureResult(failure);

        await emit([const StorePurchased('heart_100', 'tok')]);

        expect((state().phase, state().banner), (HeartPurchasePhase.delayed, HeartPurchaseNotice.delayed));
        repo.outcome = const Success(PurchaseGranted(hearts: 100, bonusHearts: 50, isNew: true));
        gateway.unconsumed = const [StorePurchased('heart_100', 'tok')];
        await openStore();
        expect(repo.verified, [('heart_100', 'tok'), ('heart_100', 'tok')]);
        expect((state().toast! as GrantedToast).message, '150하트가 들어왔어요(보너스 50 포함)');
      });
    }

    test('409 다른 계정 → 배너, 같은 토큰은 다시 보내지 않는다', () async {
      repo.outcome = const FailureResult(ServerRejectedFailure('x', code: 'purchase_other_account'));

      await emit([const StorePurchased('heart_100', 'tok')]);
      await emit([const StorePurchased('heart_100', 'tok')]);

      expect((state().phase, state().banner), (HeartPurchasePhase.idle, HeartPurchaseNotice.otherAccount));
      expect(repo.verified, hasLength(1));
    });

    test('409 이미 처리 → "이미 처리된 결제예요" 토스트', () async {
      repo.outcome = const FailureResult(ServerRejectedFailure('x', code: 'purchase_token_used'));

      await emit([const StorePurchased('heart_100', 'tok')]);

      expect((state().toast! as NoticeToast).notice, HeartPurchaseNotice.alreadyProcessed);
      expect(state().banner, isNull);
    });

    test('422 확인 실패 → 배너, 같은 토큰은 다시 보내지 않는다', () async {
      repo.outcome = const FailureResult(ServerRejectedFailure('x', code: 'purchase_invalid'));

      await emit([const StorePurchased('heart_100', 'tok')]);
      gateway.unconsumed = const [StorePurchased('heart_100', 'tok')];
      await openStore();

      expect(state().banner, isNull, reason: '상점에 다시 들어오면 배너는 지워진다');
      expect(repo.verified, hasLength(1));
    });

    test('여러 건이 한꺼번에 와도 하나씩 차례로 보낸다', () async {
      repo.holdVerify = Completer<void>();

      gateway.emit([const StorePurchased('heart_100', 't1'), const StorePurchased('heart_200', 't2')]);
      gateway.emit([const StorePurchased('heart_400', 't3')]);
      await pumpEventQueue();
      expect(repo.verified, [('heart_100', 't1')]);
      repo.holdVerify!.complete();
      await pumpEventQueue();

      expect(repo.verified, [('heart_100', 't1'), ('heart_200', 't2'), ('heart_400', 't3')]);
      expect(repo.maxRunning, 1);
    });

    test('확인 중인 토큰이 복구로 또 와도(결제 창에서 돌아온 복귀) 한 번만 보낸다', () async {
      repo.holdVerify = Completer<void>();
      gateway.emit([const StorePurchased('heart_100', 'tok')]);
      await pumpEventQueue();

      gateway.unconsumed = const [StorePurchased('heart_100', 'tok')];
      await vm().refresh();
      await pumpEventQueue();
      repo.holdVerify!.complete();
      await pumpEventQueue();

      expect(repo.verified, [('heart_100', 'tok')]);
    });

    test('확인이 예기치 않게 던져도 줄이 멈추지 않고, 그 토큰은 다음 복구 때 다시 보낸다(지급 지연)', () async {
      repo.throwOnVerify = StateError('계약 밖');
      await emit([const StorePurchased('heart_100', 'tok')]);
      expect((state().phase, state().banner), (HeartPurchasePhase.delayed, HeartPurchaseNotice.delayed));

      repo.throwOnVerify = null;
      await emit([const StorePurchased('heart_200', 'next')]);
      gateway.unconsumed = const [StorePurchased('heart_100', 'tok')];
      await openStore();

      expect(repo.verified, [('heart_100', 'tok'), ('heart_200', 'next'), ('heart_100', 'tok')]);
    });

    test('clearToast 는 토스트만 지운다', () async {
      await emit([const StorePurchaseCanceled('')]);

      vm().clearToast();

      expect(state().toast, isNull);
    });
  });

  group('구매를 끝내는 때(finish — 구글 창구는 아무것도 하지 않고, 애플 창구는 거래를 끝낸다)', () {
    setUp(() async {
      await openStore();
      await vm().buy();
    });

    test('구글도 같은 길 — 서버가 지급했다고 답한 뒤에 finish 를 부른다(구글 창구에서는 소비를 서버가 하므로 아무 일 없음)', () async {
      await emit([const StorePurchased('heart_100', 'tok')]);

      expect(repo.verified, [('heart_100', 'tok')]);
      expect(repo.appleVerified, isEmpty);
      expect(gateway.finished, ['tok']);
    });

    test('서버 202(구글 대기)는 끝내지 않는다', () async {
      repo.outcome = const Success(PurchasePendingAtStore());

      await emit([const StorePurchased('heart_100', 'tok')]);

      expect(gateway.finished, isEmpty);
    });
  });

  group('App Store(iOS)', () {
    const transactionId = '2000000123456789';

    setUp(() => container = makeContainer(store: PaymentStore.appStore));

    test('결제 창에는 apple_account_token(UUID)을 싣는다 — 구글용 64자 계정 표시가 아니다', () async {
      await openStore();

      await vm().buy();

      expect(gateway.bought, [('heart_100', fakeAppleAccountToken)]);
    });

    test('애플 계정 표시를 주지 않는 서버(배포 전)면 iOS 는 결제 불가 배너 — 구글 표시로 대신 사지 않는다', () async {
      repo.status = Success(BillingStatus(accountToken: fakeAccountToken, bonus: fakeBonus));

      await openStore();

      expect((state().availability, state().banner), (HeartStoreAvailability.unavailable, HeartPurchaseNotice.unavailable));
      expect(state().canBuy('heart_100'), isFalse);
    });

    test('결제됨 → /billing/apple/verify 에 (상품, 거래 번호), 구글 확인은 부르지 않는다', () async {
      await openStore();

      await emit([const StorePurchased('heart_200', transactionId)]);

      expect(repo.appleVerified, [('heart_200', transactionId)]);
      expect(repo.verified, isEmpty);
    });

    test('서버 200(granted) 뒤에만 거래를 끝낸다 — 확인 중에는 끝내지 않는다', () async {
      await openStore();
      repo.holdVerify = Completer<void>();

      await emit([const StorePurchased('heart_100', transactionId)]);
      expect(gateway.finished, isEmpty, reason: '서버가 지급하기 전에 끝내면 지급이 늦어진 결제를 되살릴 수 없다');
      repo.holdVerify!.complete();
      await pumpEventQueue();

      expect(gateway.finished, [transactionId]);
      expect((state().toast! as GrantedToast).message, '150하트가 들어왔어요(보너스 50 포함)');
    });

    test('이미 받은 거래(already_granted)도 끝낸다 — 하트는 이미 들어갔다', () async {
      await openStore();
      repo.outcome = const Success(PurchaseGranted(hearts: 100, bonusHearts: 0, isNew: false));

      await emit([const StorePurchased('heart_100', transactionId)]);

      expect(gateway.finished, [transactionId]);
    });

    for (final failure in const <Failure>[ServerUnavailableFailure(), NetworkFailure(), UnknownFailure()]) {
      test('${failure.runtimeType}(503 billing_unavailable · apple_not_configured 포함) → 끝내지 않고 지급 지연, 다음 복구 때 다시 보낸다', () async {
        await openStore();
        repo.outcome = FailureResult(failure);

        await emit([const StorePurchased('heart_100', transactionId)]);

        expect((state().phase, state().banner), (HeartPurchasePhase.delayed, HeartPurchaseNotice.delayed));
        expect(gateway.finished, isEmpty);
        repo.outcome = const Success(PurchaseGranted(hearts: 100, bonusHearts: 50, isNew: true));
        gateway.unconsumed = const [StorePurchased('heart_100', transactionId)];
        await openStore();
        expect(repo.appleVerified, [('heart_100', transactionId), ('heart_100', transactionId)]);
        expect(gateway.finished, [transactionId]);
      });
    }

    test('409 다른 계정 → 끝내지 않는다(결제한 계정으로 로그인하면 StoreKit 이 다시 줘서 들어온다), 이번 로그인에서는 다시 보내지 않는다', () async {
      await openStore();
      repo.outcome = const FailureResult(ServerRejectedFailure('x', code: 'purchase_other_account'));

      await emit([const StorePurchased('heart_100', transactionId)]);
      gateway.unconsumed = const [StorePurchased('heart_100', transactionId)];
      await vm().refresh();
      await pumpEventQueue();

      expect(state().banner, HeartPurchaseNotice.otherAccount);
      expect(repo.appleVerified, hasLength(1));
      expect(gateway.finished, isEmpty);
    });

    test('422 확인 실패 → 끝내지 않는다(서버를 고치면 다음 앱 시작 때 다시 확인된다), 이번 로그인에서는 다시 보내지 않는다', () async {
      await openStore();
      repo.outcome = const FailureResult(ServerRejectedFailure('x', code: 'purchase_invalid'));

      await emit([const StorePurchased('heart_100', transactionId)]);
      gateway.unconsumed = const [StorePurchased('heart_100', transactionId)];
      await vm().refresh();
      await pumpEventQueue();

      expect(state().banner, HeartPurchaseNotice.invalid);
      expect(repo.appleVerified, hasLength(1));
      expect(gateway.finished, isEmpty);
    });

    test('409 이미 처리(purchase_token_used) → 하트가 이미 들어간 거래라 끝낸다(남겨 두면 같은 상품을 다시 못 산다)', () async {
      await openStore();
      repo.outcome = const FailureResult(ServerRejectedFailure('x', code: 'purchase_token_used'));

      await emit([const StorePurchased('heart_100', transactionId)]);

      expect((state().toast! as NoticeToast).notice, HeartPurchaseNotice.alreadyProcessed);
      expect(gateway.finished, [transactionId]);
    });
  });

  group('구매를 여는 기기(heartPurchaseSupportedProvider)', () {
    bool supportedOn(TargetPlatform platform) {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final plain = ProviderContainer();
      addTearDown(plain.dispose);
      return plain.read(heartPurchaseSupportedProvider);
    }

    test('안드로이드(구글 플레이) · iOS(App Store)는 연다', () {
      expect((supportedOn(TargetPlatform.android), supportedOn(TargetPlatform.iOS)), (true, true));
    });

    test('그 밖(데스크톱)은 숨긴다', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux, TargetPlatform.fuchsia]) {
        expect(supportedOn(platform), isFalse, reason: platform.name);
      }
    });
  });

  test('앱이 꺼진 사이의 결제 — 시작 때 복구가 흘려 준 결제를 서버로 보내 지급한다', () async {
    gateway.unconsumed = const [StorePurchased('heart_400', 'old')];

    await vm().refresh();
    await pumpEventQueue();

    expect(repo.verified, [('heart_400', 'old')]);
    expect(state().phase, HeartPurchasePhase.idle);
  });

  test('구독은 뷰모델 하나가 앱 수명 동안 — 상점을 열지 않아도 늦게 온 결제를 받는다', () async {
    container.read(heartPurchaseViewModelProvider);

    gateway.emit([const StorePurchased('heart_100', 'late')]);
    await pumpEventQueue();

    expect(repo.verified, [('heart_100', 'late')]);
  });
}
