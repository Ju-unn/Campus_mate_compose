import 'dart:async';
import 'dart:convert';

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/push/push_provider.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/main.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat/model/fake_chat_repository.dart';
import 'core/push/fake_push_messaging.dart';
import 'home/model/fake_home_repository.dart';
import 'matching/model/fake_card_repository.dart';
import 'profile/model/fake_onboarding_repository.dart';

/// 관문 조회가 [complete] 를 부를 때까지 끝나지 않는다 — 콜드 스타트에서 서버가 늦게 답하는 모양.
class _SlowGateRepository implements VerificationGateRepository {
  final _answer = Completer<Result<VerificationGate>>();

  void complete(VerificationGate gate) => _answer.complete(Success(gate));

  @override
  Future<Result<VerificationGate>> fetchGate() => _answer.future;
}

/// 꺼진 앱에서 알림을 눌러 켰을 때(A10). 알림 경로는 관문 조회가 끝난 뒤에 열린다 —
/// 먼저 열면 조회 전 기본값(약관 동의)에 끌려갔다가 조회가 오면 홈으로 가서 목표 화면을 놓쳤다.
void main() {
  // main_account_status_test.dart 와 같은 더미 초기화 — CampusMateApp 이 Supabase 세션을 직접 읽는다.
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

  testWidgets('관문 조회가 늦게 와도 받은 수락 알림의 대화 목록으로 간다', (tester) async {
    final gate = _SlowGateRepository();
    final container = ProviderContainer(
      overrides: [
        verificationGateRepositoryProvider.overrideWithValue(gate),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
        pushMessagingProvider.overrideWithValue(
          FakePushMessaging(token: 't', granted: false, initial: {'route': 'acceptances'}),
        ),
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
        signOutProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    // 스플래시(SplashHold 2초)가 지나도록 관문은 아직 답하지 않았다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    gate.complete(VerificationGate.complete);
    await tester.pumpAndSettle();

    expect(find.byType(ConversationsScreen), findsOneWidget);
  });
}
