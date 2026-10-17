import 'dart:convert';

import 'package:campus_mate/auth/model/school_name_provider.dart';
import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/billing/model/billing_repository_provider.dart';
import 'package:campus_mate/billing/model/heart_store_gateway.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_view_model.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/main.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/model/fake_verification_gate_repository.dart';
import 'billing/model/fake_billing_repository.dart';
import 'billing/model/fake_heart_store_gateway.dart';
import 'chat/model/fake_chat_repository.dart';
import 'core/push/fake_push_messaging.dart';
import 'home/model/fake_home_repository.dart';
import 'matching/model/fake_card_repository.dart';
import 'notifications/model/fake_notifications_repository.dart';
import 'profile/model/fake_onboarding_repository.dart';

/// 하트 결제 구독은 상점이 아니라 앱 루트가 연다 — 로그인 뒤 관문이 열리면 한 번(계획서 6-1 ①, 대장 지시 10-13 "앱 수명 동안 한 곳에서").
void main() {
  // main_push_open_test.dart 와 같은 더미 초기화 — CampusMateApp 이 Supabase 세션을 직접 읽는다.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') {
        return <String, Object>{};
      }
      return true;
    });
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  GoTrueClient auth() => Supabase.instance.client.auth;

  setUp(() => auth().setInitialSession(jsonEncode({
        'access_token': 'test-access-token',
        'token_type': 'bearer',
        'user': {'id': 'u1', 'aud': 'authenticated', 'created_at': '2026-10-03T00:00:00Z'},
      })));

  tearDown(() async {
    try {
      await auth().signOut();
    } on AuthException {
      // 서버 알림은 테스트 바인딩의 가짜 HTTP 가 막는다 — 이 기기 세션은 이미 지워졌다.
    }
  });

  late FakeHeartStoreGateway store;
  late FakeBillingRepository billing;

  /// [byPlatform] 이면 구매를 여는지 · 어느 스토어인지를 덮지 않는다 — 시험 플랫폼(variant)대로 진짜 provider 가 정한다.
  Future<void> pumpApp(
    WidgetTester tester, {
    VerificationGate gate = VerificationGate.complete,
    bool byPlatform = false,
    List<StorePurchaseEvent> unconsumed = const [StorePurchased('heart_100', 'paid-before-crash')],
  }) async {
    store = FakeHeartStoreGateway();
    billing = FakeBillingRepository();
    final container = ProviderContainer(
      overrides: [
        verificationGateRepositoryProvider.overrideWithValue(FakeVerificationGateRepository()..nextResult = Success(gate)),
        // 관문이 남은 계정은 3c 에 선다 — 학교 이름을 Supabase 에서 읽지 않게 덮는다.
        schoolNameProvider.overrideWithValue(const AsyncData<String>('서울대학교')),
        // 3c 학교 줄(SchoolLabel)이 로고 표를 읽는다 — 진짜 Supabase 조회가 실패해 재시도 타이머가 남지 않게.
        universityLogosProvider.overrideWith((ref) => const <String, String>{}),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        pushMessagingProvider.overrideWithValue(FakePushMessaging(token: 't', granted: false)),
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        // 관문이 열리면 앱이 사용자 채널을 연다 — 시험에서는 진짜 Realtime 소켓을 열지 않는다.
        userEventStreamProvider.overrideWithValue(FakeUserEventStream()),
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
        notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
        signOutProvider.overrideWithValue(() async {}),
        heartStoreGatewayProvider.overrideWithValue(store),
        billingRepositoryProvider.overrideWithValue(billing),
        if (!byPlatform) heartPurchaseSupportedProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);
    store.unconsumed = unconsumed;
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  testWidgets('관문이 열리면(앱 시작) 소비 안 된 지난 결제를 복구해 서버로 보낸다 — 상점을 열지 않아도', (tester) async {
    await pumpApp(tester);

    expect(store.recoverCount, 1);
    expect(billing.verified, [('heart_100', 'paid-before-crash')]);
  });

  testWidgets('상점이 닫혀 있어도 늦게 온 결제(느린 결제가 결제됨으로)를 받는다', (tester) async {
    await pumpApp(tester);

    store.emit(const [StorePurchased('heart_200', 'late')]);
    await tester.pumpAndSettle();

    expect(billing.verified.last, ('heart_200', 'late'));
  });

  testWidgets('iOS — 관문이 열리면 끝내지 않은 애플 거래를 거래 번호로 애플 확인에 보내고, 지급된 뒤에 끝낸다', (tester) async {
    await pumpApp(tester, byPlatform: true, unconsumed: const [StorePurchased('heart_100', '2000000123456789')]);

    expect(store.recoverCount, 1);
    expect(billing.appleVerified, [('heart_100', '2000000123456789')]);
    expect(billing.verified, isEmpty, reason: '구글 확인으로 보내지 않는다');
    expect(store.finished, ['2000000123456789']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('안드로이드도 기기 그대로 구매를 열고 구글 확인으로 보낸다(구글 경로 불변)', (tester) async {
    await pumpApp(tester, byPlatform: true);

    expect(billing.verified, [('heart_100', 'paid-before-crash')]);
    expect(billing.appleVerified, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('관문이 열리기 전(학과 입력 전)에는 하트 결제를 건드리지 않는다 — 서버 확인은 관문 뒤', (tester) async {
    await pumpApp(tester, gate: VerificationGate.needsSchoolInfo);

    expect((store.availableCount, store.recoverCount, billing.verified.length), (0, 0, 0));
  });
}
