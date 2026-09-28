import 'dart:async';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/billing/view/heart_tasks_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_heart_task_repository.dart';

void main() {
  late FakeHeartTaskRepository repository;

  setUp(() => repository = FakeHeartTaskRepository());

  /// 설정(16)에서 18a 로 들어온 것처럼 한 번 push 한다 — 뒤로 버튼이 보이게.
  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (context, state) => const Text('설정')),
        GoRoute(path: AppRoutes.heartTasks, builder: (context, state) => const HeartTasksScreen()),
        GoRoute(path: '${AppRoutes.heartTaskSubmit}/:task', builder: (context, state) => Text('제출 ${state.uri}')),
        GoRoute(path: AppRoutes.community, builder: (context, state) => const Text('커뮤니티')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [heartTaskRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    unawaited(router.push(AppRoutes.heartTasks));
    await tester.pumpAndSettle();
  }

  testWidgets('pen 18a — 제목 · 안내 · 세 줄의 글자와 상태 칩', (tester) async {
    await pump(tester);

    expect(find.text('무료로 하트 모으기'), findsOneWidget);
    expect(find.text('초기 보상 기준 · 인증 후 지급\n100명 이후 홍보 30 / 단톡방 20 하트'), findsOneWidget);
    expect(find.text('무료로 모으기'), findsNothing);
    expect(find.text('에브리타임 홍보'), findsOneWidget);
    expect(find.text('50 · 월 1회'), findsOneWidget);
    expect(find.text('검수중'), findsOneWidget);
    expect(find.text('학교 단톡방 공유'), findsOneWidget);
    expect(find.text('25 · 월 3회'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);
    expect(find.text('커뮤니티 투표'), findsOneWidget);
    expect(find.text('매일'), findsOneWidget);
    // pen `Uaex2` 알약 높이 20(글자 칸 16 + 위아래 2).
    expect(tester.getSize(find.ancestor(of: find.text('매일'), matching: find.byType(Container)).first).height, 20);
    expect(find.text('10 · 주 최대 30'), findsOneWidget);
    expect(find.text('참여'), findsOneWidget);
    expect(find.image(const AssetImage('assets/images/heart-flat-vector-v3.png')), findsNWidgets(3));
  });

  testWidgets('pen 치수 — 줄 328×64 · 줄 사이 8 · 안내에서 첫 줄 24 · 칩 72×28', (tester) async {
    await pump(tester);

    final rows = find.byType(HeartTaskRow);
    final first = tester.getRect(rows.at(0));
    final second = tester.getRect(rows.at(1));
    expect(first.left, 16);
    expect(first.size, const Size(328, 64));
    expect(second.top - first.bottom, 8);
    expect(first.top - tester.getRect(find.textContaining('초기 보상 기준')).bottom, 24);
    final chip = find.ancestor(of: find.text('검수중'), matching: find.byType(ConstrainedBox)).first;
    expect(tester.getSize(chip), const Size(72, 28));
  });

  testWidgets('뒤로 누름 영역은 48 이고 아이콘은 x16 에서 시작한다', (tester) async {
    await pump(tester);

    final back = find.ancestor(of: find.byIcon(AppIcons.arrowLeft), matching: find.byType(IconButton));
    expect(tester.getSize(back), const Size(48, 48));
    expect(tester.getRect(find.byIcon(AppIcons.arrowLeft)).left, 16);
    expect(tester.getRect(find.text('무료로 하트 모으기')).left, 52);
  });

  testWidgets('미완료 인증 항목은 "인증하기" 이고 누르면 18b', (tester) async {
    repository.tasks = Success(sampleHeartTasks(everytime: HeartTaskState.open));
    await pump(tester);

    expect(find.text('인증하기'), findsOneWidget);
    await tester.tap(find.text('에브리타임 홍보'));
    await tester.pumpAndSettle();

    expect(find.text('제출 /heart-tasks/submit/everytime_post'), findsOneWidget);
  });

  testWidgets('반려 줄은 "다시 제출" 글자가 아니라 줄 전체가 눌리고 사유를 18b-2 로 넘긴다', (tester) async {
    repository.tasks = Success(
      sampleHeartTasks(everytime: HeartTaskState.rejected, everytimeReason: HeartTaskRejectReason.dateMissing),
    );
    await pump(tester);

    expect(find.text('다시 제출'), findsOneWidget);
    await tester.tap(find.byIcon(AppIcons.megaphone));
    await tester.pumpAndSettle();

    expect(find.text('제출 /heart-tasks/submit/everytime_post?reason=date_missing'), findsOneWidget);
  });

  testWidgets('검수중 · 완료 줄은 누를 수 없다', (tester) async {
    await pump(tester);

    for (final title in ['에브리타임 홍보', '학교 단톡방 공유']) {
      expect(find.ancestor(of: find.text(title), matching: find.byType(InkWell)), findsNothing);
    }
  });

  testWidgets('투표 미완료 줄을 누르면 커뮤니티 탭으로 간다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('커뮤니티 투표'));
    await tester.pumpAndSettle();

    expect(find.text('커뮤니티'), findsOneWidget);
  });

  testWidgets('누르는 줄의 잉크는 줄 자신의 Material 에 그린다(COMMON §4-2)', (tester) async {
    await pump(tester);

    final label = find.text('커뮤니티 투표');
    final tile = find.ancestor(of: label, matching: find.byType(InkWell)).first;
    final painter = find.ancestor(of: label, matching: find.byType(Material)).first;
    expect(tester.getSize(painter), tester.getSize(tile));
  });

  testWidgets('읽기 실패면 문구와 "다시 시도", 누르면 다시 읽는다', (tester) async {
    repository.tasks = const FailureResult(NetworkFailure());
    await pump(tester);

    expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
    repository.tasks = Success(sampleHeartTasks());
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('에브리타임 홍보'), findsOneWidget);
    expect(repository.fetchCount, 2);
  });

  testWidgets('글자 2배에서도 넘침 예외가 없다(반려 줄 포함)', (tester) async {
    repository.tasks = Success(
      sampleHeartTasks(everytime: HeartTaskState.rejected, everytimeReason: HeartTaskRejectReason.reused),
    );
    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('다시 제출'), findsOneWidget);
  });
}
