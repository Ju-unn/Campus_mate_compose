import 'package:campus_mate/core/app_update/update_required_screen.dart';
import 'package:campus_mate/core/app_update/update_requirement.dart';
import 'package:campus_mate/core/app_update/update_requirement_provider.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _storeUrl = 'https://play.google.com/store/apps/details?id=io.github.juunn.campusmate';

/// 강제 업데이트 안내(01-2)를 앱 루트에 거는 배선(main.dart)을 지킨다 — 게이트 자체는 update_gate_test.dart 가 본다.
/// 여기는 ① 앱 전체(라우터 위)가 안내 화면으로 바뀌는지 ② 앱이 백그라운드에서 돌아올 때 다시 묻는지만 본다.
void main() {
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

  late int asks;
  late UpdateRequirement nextAnswer;

  setUp(() => asks = 0);

  Future<void> pumpApp(WidgetTester tester, UpdateRequirement answer) async {
    nextAnswer = answer;
    final container = ProviderContainer(
      overrides: [
        signOutProvider.overrideWithValue(() async {}),
        updateRequirementProvider.overrideWith((ref) async {
          asks++;
          return nextAnswer;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CampusMateApp()));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  /// 앞 → 뒤 → 앞. 단계는 하나씩 밟아야 한다(inactive ↔ hidden ↔ paused).
  Future<void> backgroundAndBack(WidgetTester tester) async {
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    // supabase_flutter 는 앞으로 돌아오면 토큰 자동 갱신 타이머를 켠다 — 시험이 끝나기 전에 끈다.
    Supabase.instance.client.auth.stopAutoRefresh();
  }

  testWidgets('업데이트가 필요하면 앱 전체가 안내 화면으로 막힌다', (tester) async {
    await pumpApp(tester, const UpdateRequired(_storeUrl));

    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.text('새 버전으로 업데이트해 주세요'), findsOneWidget);
    expect(find.byType(Navigator), findsNothing); // 라우터(화면 전부)는 그려지지 않는다
  });

  testWidgets('필요 없으면 안내 화면 없이 앱이 그대로 뜬다', (tester) async {
    await pumpApp(tester, const UpdateNotRequired());

    expect(find.byType(UpdateRequiredScreen), findsNothing);
    expect(find.byType(Navigator), findsWidgets);
  });

  testWidgets('앱이 백그라운드에서 돌아오면 업데이트가 필요한지 다시 묻는다 — 로그아웃 상태에서도', (tester) async {
    await pumpApp(tester, const UpdateNotRequired());
    expect(asks, 1);

    await backgroundAndBack(tester);

    expect(asks, 2);
  });

  testWidgets('막혀 있다가 돌아왔을 때 이제 괜찮다고 나오면 안내 화면이 걷히고 앱(라우터)이 다시 뜬다', (tester) async {
    await pumpApp(tester, const UpdateRequired(_storeUrl));
    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    nextAnswer = const UpdateNotRequired(); // 그 사이 서버가 최소 버전을 거뒀다

    await backgroundAndBack(tester);

    expect(find.byType(UpdateRequiredScreen), findsNothing);
    expect(find.byType(Navigator), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
