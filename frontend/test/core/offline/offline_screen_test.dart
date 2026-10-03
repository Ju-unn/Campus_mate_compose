import 'dart:async';

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/auth/model/verification_gate_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/offline/offline_screen.dart';
import 'package:campus_mate/core/router/verification_gate_listenable_provider.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../auth/model/fake_verification_gate_repository.dart';
import '../../profile/model/fake_onboarding_repository.dart';

/// 온보딩 단계 조회를 문 앞에 세워 둘 수 있는 가짜 — 관문보다 먼저 묻는지 본다.
class _GatedOnboardingRepository extends FakeOnboardingRepository {
  Completer<void>? gate;

  /// 묻기 시작한 횟수 — 문 앞에 서 있는 동안에도 센다([fetchCount] 는 문을 지난 뒤에 오른다).
  int startCount = 0;

  @override
  Future<Result<OnboardingStep>> fetchNextStep() async {
    startCount++;
    await gate?.future;
    return super.fetchNextStep();
  }
}

void main() {
  late FakeVerificationGateRepository gate;
  late _GatedOnboardingRepository onboarding;

  setUp(() {
    gate = FakeVerificationGateRepository();
    onboarding = _GatedOnboardingRepository();
  });

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        verificationGateRepositoryProvider.overrideWithValue(gate),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: OfflineScreen())),
    );
    return container;
  }

  ElevatedButton retryButton(WidgetTester tester) => tester.widget<ElevatedButton>(find.byType(ElevatedButton));

  testWidgets('인터넷 연결 안내와 다시 시도 버튼을 보여준다', (tester) async {
    await pumpScreen(tester);

    expect(find.text('인터넷 연결을 확인해 주세요'), findsOneWidget);
    expect(find.text('연결되면 하던 곳으로 돌아갈게요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('안내 위에 3D 파란 느낌표(pen s3b4k)를 120 으로 둔다', (tester) async {
    await pumpScreen(tester);

    final icon = tester.widget<Icon3d>(find.byType(Icon3d));
    expect(icon.icon, AppIcon3d.infoBlue);
    expect(icon.size, 120);
  });

  testWidgets('pen NWGuf 처럼 안내는 위 여백 120 아래, 버튼은 바닥 40 위에 있다', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpScreen(tester);

    // 안내(Empty q6NzJ)는 위 여백 WqP2S 120 + 간격 20 아래에서 시작한다 — 안쪽 여백 48 뒤에 아이콘이 온다.
    expect(tester.getTopLeft(find.byKey(const ValueKey('offline-notice'))).dy, 120 + 20);
    // 버튼(NvqcP)은 프레임 아래 안쪽 여백 40 위에 붙는다. 좌우 24.
    final button = tester.getRect(find.byType(ElevatedButton));
    expect(button.bottom, 780 - 40);
    expect(button.left, 24);
    expect(button.right, 360 - 24);
  });

  testWidgets('글자를 2배로 키워도 넘치지 않고 버튼은 바닥에 남는다', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScreen(tester);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(ElevatedButton)).bottom, 640 - 40);
  });

  testWidgets('다시 시도하면 온보딩 단계를 먼저 묻고 그다음 관문을 묻는다', (tester) async {
    // 관문이 먼저 바뀌면 라우터가 온보딩 캐시 기본값(04-1)으로 온보딩을 마친 사람을 보낸다.
    final container = await pumpScreen(tester);
    onboarding.gate = Completer<void>();

    await tester.tap(find.text('다시 시도'));
    await tester.pump();

    expect(onboarding.startCount, 1);
    expect(gate.fetchCount, 0);
    expect(retryButton(tester).onPressed, isNull); // 묻는 동안 버튼은 스피너로 잠긴다
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    onboarding.gate!.complete();
    await tester.pumpAndSettle();

    expect(gate.fetchCount, 1);
    expect(container.read(verificationGateListenableProvider).value, VerificationGate.complete);
  });

  testWidgets('다시 실패하면 그 화면 그대로 다시 누를 수 있다(토스트 없음)', (tester) async {
    gate.nextResult = const FailureResult(NetworkFailure());
    final container = await pumpScreen(tester);
    await container.read(verificationGateListenableProvider).refresh(); // 앱을 켤 때의 첫 실패

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(container.read(verificationGateListenableProvider).value, VerificationGate.unreachable);
    expect(retryButton(tester).onPressed, isNotNull);
    expect(find.byType(SnackBar), findsNothing);
  });
}
