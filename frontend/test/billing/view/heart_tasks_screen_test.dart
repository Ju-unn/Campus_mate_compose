import 'dart:async';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/billing/view/heart_tasks_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../model/fake_heart_task_repository.dart';

/// 지운 내부용 보상 기준 글(사용자 10-16 "Node ID: eAKKO 이거지워 우리만 아는거야") — 18a 에서도 보이면 안 된다.
const _removedNotice = '초기 보상 기준';

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

  testWidgets('pen 18a — 제목 · 세 줄의 글자와 상태 칩, 내부용 보상 기준 안내는 없다', (tester) async {
    await pump(tester);

    expect(find.text('무료로 하트 모으기'), findsOneWidget);
    expect(find.textContaining(_removedNotice), findsNothing);
    expect(find.textContaining('100명 이후'), findsNothing);
    expect(find.text('무료로 모으기'), findsNothing);
    expect(find.text('에브리타임 홍보'), findsOneWidget);
    expect(find.text('40 · 월 1회'), findsOneWidget);
    expect(find.text('검수중'), findsOneWidget);
    expect(find.text('단톡방 공유'), findsOneWidget);
    expect(find.text('25 · 월 3회'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);
    expect(find.text('커뮤니티 투표'), findsOneWidget);
    // 투표 배지 글자는 "하루 1번"(사용자 결정 10-12, 종전 pen "매일" — pen 동기화 대기).
    expect(find.text('하루 1번'), findsOneWidget);
    expect(find.text('매일'), findsNothing);
    // pen `Uaex2` 알약 높이 20(글자 칸 16 + 위아래 2) — 글자가 길어져도 한 줄.
    expect(tester.getSize(find.ancestor(of: find.text('하루 1번'), matching: find.byType(Container)).first).height, 20);
    expect(find.text('5 · 주 최대 15'), findsOneWidget);
    expect(find.text('참여'), findsOneWidget);
    expect(find.image(const AssetImage('assets/images/heart-flat-vector-v3.png')), findsNWidgets(3));
  });

  testWidgets('pen 치수 — 줄 328×64 · 줄 사이 8 · 첫 줄은 목록 맨 위(앱바 56 + 8) · 칩 72×28', (tester) async {
    await pump(tester);

    final rows = find.byType(HeartTaskRow);
    final first = tester.getRect(rows.at(0));
    final second = tester.getRect(rows.at(1));
    expect(first.left, 16);
    expect(first.size, const Size(328, 64));
    expect(second.top - first.bottom, 8);
    // 안내를 지우며 안내와 첫 줄 사이(섹션 간격 8 + 빈칸 `vlmhj` 8 + 간격 8)도 같이 걷었다 — 18a 의 지운 뒤 pen 값은 받지 못했다.
    expect(first.top, 56 + 8);
    // 시계 칩은 시험 글꼴 글자가 Pretendard 보다 넓어 72 를 넘는다 — 폭은 완료 칩으로 잰다.
    final chip = find.ancestor(of: find.text('완료'), matching: find.byType(ConstrainedBox)).first;
    expect(tester.getSize(chip), const Size(72, 28));
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale — 첫 줄은 목록 맨 위(앱바 56 + 8) 그대로, 넘치지 않는다', (tester) async {
      await pump(tester, textScale: scale);

      expect(tester.getRect(find.byType(HeartTaskRow).first).top, 56 + 8);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pen 18a 아이콘 —줄마다 3D 28 이 x0 · 줄 가운데(공유 n40Hd · 투표 x5QLa), 검수중 칩 시계 3D 16(e2aMg · oq6tX)', (tester) async {
    await pump(tester);

    Finder icon3d(AppIcon3d icon) => find.byWidgetPredicate((w) => w is Icon3d && w.icon == icon);
    final rows = find.byType(HeartTaskRow);
    for (final (i, icon) in [AppIcon3d.megaphone, AppIcon3d.share, AppIcon3d.vote].indexed) {
      final row = tester.getRect(rows.at(i));
      final rect = tester.getRect(find.descendant(of: rows.at(i), matching: icon3d(icon)));
      expect(rect.size, const Size(28, 28));
      // pen y18 — 아래 선 1 이 칸을 먹어 17.5.
      expect(rect.left, row.left);
      expect(rect.top - row.top, closeTo(18, 0.5));
    }
    final chip = find.ancestor(of: find.text('검수중'), matching: find.byType(ConstrainedBox)).first;
    expect(tester.getSize(find.descendant(of: chip, matching: icon3d(AppIcon3d.clock))), const Size(16, 16));
    expect(tester.getSize(chip).height, 28);
    // 완료 칩은 그대로 lucide check 12 primaryText.
    final done = find.ancestor(of: find.text('완료'), matching: find.byType(ConstrainedBox)).first;
    final check = tester.widget<Icon>(find.descendant(of: done, matching: find.byIcon(AppIcons.check)));
    expect((check.size, check.color), (12.0, AppColors.primaryText));
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
    await tester.tap(find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.megaphone));
    await tester.pumpAndSettle();

    expect(find.text('제출 /heart-tasks/submit/everytime_post?reason=date_missing'), findsOneWidget);
  });

  testWidgets('검수중 · 완료 줄은 누를 수 없다', (tester) async {
    await pump(tester);

    for (final title in ['에브리타임 홍보', '단톡방 공유']) {
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
    // "하루 1번" 배지는 2배에서도 한 줄(글자 칸 16×2 + 위아래 2) — 넘치면 제목 쪽이 접힌다.
    expect(tester.getSize(find.ancestor(of: find.text('하루 1번'), matching: find.byType(Container)).first).height, 36);
  });

  testWidgets('투표 배지는 낭독도 "하루 1번" 이다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(find.bySemanticsLabel(RegExp('하루 1번')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('매일')), findsNothing);
    handle.dispose();
  });
}
