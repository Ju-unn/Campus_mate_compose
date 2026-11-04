import 'dart:async';

import 'package:campus_mate/core/app_update/update_gate.dart';
import 'package:campus_mate/core/app_update/update_required_screen.dart';
import 'package:campus_mate/core/app_update/update_requirement.dart';
import 'package:campus_mate/core/app_update/update_requirement_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../billing/store/view/pretendard.dart';

const _storeUrl = 'https://play.google.com/store/apps/details?id=io.github.juunn.campusmate';

void main() {
  late int exitCalls;

  setUpAll(loadPretendard);
  setUp(() => exitCalls = 0);

  /// main.dart 와 같은 자리 — `MaterialApp.builder` 가 받은 child(라우터 · 내비게이터)를 게이트로 감싼다.
  Future<ProviderContainer> pumpApp(
    WidgetTester tester,
    Future<UpdateRequirement> Function() decide,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exitCalls++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final container = ProviderContainer(overrides: [updateRequirementProvider.overrideWith((ref) => decide())]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => UpdateGate(child: child!),
          home: const Scaffold(body: Text('앱 본문')),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('업데이트가 필요하면 안내 화면을 그리고 앱 본문은 그리지 않는다', (tester) async {
    await pumpApp(tester, () async => const UpdateRequired(_storeUrl));

    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.text('새 버전으로 업데이트해 주세요'), findsOneWidget);
    expect(find.text('앱 본문'), findsNothing);
  });

  testWidgets('안내 화면에 스토어 주소를 그대로 넘긴다', (tester) async {
    await pumpApp(tester, () async => const UpdateRequired(_storeUrl));

    expect(tester.widget<UpdateRequiredScreen>(find.byType(UpdateRequiredScreen)).storeUrl, _storeUrl);
  });

  testWidgets('필요 없으면 앱 본문 그대로다', (tester) async {
    await pumpApp(tester, () async => const UpdateNotRequired());

    expect(find.text('앱 본문'), findsOneWidget);
    expect(find.byType(UpdateRequiredScreen), findsNothing);
  });

  testWidgets('조회하는 동안은 막지 않는다 — 앱 본문 그대로다', (tester) async {
    final pending = Completer<UpdateRequirement>();
    await pumpApp(tester, () => pending.future);

    expect(find.text('앱 본문'), findsOneWidget);
    expect(find.byType(UpdateRequiredScreen), findsNothing);

    pending.complete(const UpdateRequired(_storeUrl));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
  });

  testWidgets('조회가 오류로 끝나도 막지 않는다 — 앱 본문 그대로다', (tester) async {
    await pumpApp(tester, () async => throw StateError('조회 실패'));

    expect(find.text('앱 본문'), findsOneWidget);
    expect(find.byType(UpdateRequiredScreen), findsNothing);
  });

  testWidgets('다시 확인하는 동안에는 안내 화면이 깜빡이지 않고, 이제 괜찮다고 나오면 앱 본문으로 돌아온다', (tester) async {
    var answers = <Future<UpdateRequirement>>[
      Future.value(const UpdateRequired(_storeUrl)),
    ];
    final recheck = Completer<UpdateRequirement>();
    final container = await pumpApp(tester, () => answers.removeAt(0));
    answers = [recheck.future];

    container.invalidate(updateRequirementProvider);
    await tester.pump();
    expect(find.byType(UpdateRequiredScreen), findsOneWidget); // 다시 묻는 중에도 벽은 그대로

    recheck.complete(const UpdateNotRequired());
    await tester.pumpAndSettle();
    expect(find.text('앱 본문'), findsOneWidget);
    expect(find.byType(UpdateRequiredScreen), findsNothing);
  });

  group('안드로이드 시스템 뒤로가기', () {
    testWidgets('안내 화면이 떠 있으면 앱이 닫히지 않는다', (tester) async {
      await pumpApp(tester, () async => const UpdateRequired(_storeUrl));

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(exitCalls, 0);
      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    });

    testWidgets('안내 화면이 사라지면 뒤로가기는 다시 평소대로다 (비교용: 맨 아래 화면에서는 앱이 닫힌다)', (tester) async {
      await pumpApp(tester, () async => const UpdateNotRequired());

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(exitCalls, 1);
    });
  });
}
