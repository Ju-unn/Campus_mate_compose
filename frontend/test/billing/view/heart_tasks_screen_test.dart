import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_pending.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/view/heart_task_pending_list.dart';
import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/billing/view/heart_tasks_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  // pen 18a FreeSection(대장 전달 값 10-17): 제목은 꺼졌고 투명 여백 8 은 켜져 있다 — 섹션 시작 +16(여백 8 + 간격 8) · +88 · +160.
  // 본문 안쪽 위 8 이라 첫 줄은 y 56 + 8 + 16 = 80.
  testWidgets('pen 치수 — 줄 328×64 · 줄 사이 8 · 첫 줄 y80(앱바 56 + 위 8 + 여백 8 + 간격 8) · 칩 72×28', (tester) async {
    await pump(tester);

    final rows = find.byType(HeartTaskRow);
    final first = tester.getRect(rows.at(0));
    final second = tester.getRect(rows.at(1));
    expect(first.left, 16);
    expect(first.size, const Size(328, 64));
    expect(second.top - first.bottom, 8);
    expect([for (var i = 0; i < 3; i++) tester.getTopLeft(rows.at(i)).dy - (56 + 8)], [16, 88, 160]);
    // 시계 칩은 시험 글꼴 글자가 Pretendard 보다 넓어 72 를 넘는다 — 폭은 완료 칩으로 잰다.
    final chip = find.ancestor(of: find.text('완료'), matching: find.byType(ConstrainedBox)).first;
    expect(tester.getSize(chip), const Size(72, 28));
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale — 첫 줄은 y80 그대로, 넘치지 않는다', (tester) async {
      await pump(tester, textScale: scale);

      expect(tester.getRect(find.byType(HeartTaskRow).first).top, 56 + 8 + 16);
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

  // 10-18 인증샷 결과 알림 — pen 18a 반려 줄 사유(마스터 TW2ki 안 ReasonRow `ydq0k` · 아이콘 `RiCqn` · 글자 `QiLmA`,
  // 화면 `x8OCS4` 날짜 · 게시글 / `Yo8h1` 이미 쓴 캡처, 값표 1장).
  group('누를 수 있는 줄은 서버의 can_submit 이 정한다', () {
    HeartTask kakao({required HeartTaskState state, required bool canSubmit, int used = 1}) => HeartTask(
          kind: HeartTaskKind.kakaoShare,
          rewardHearts: 25,
          state: state,
          used: used,
          limit: 3,
          canSubmit: canSubmit,
          maxPhotos: 3,
        );

    testWidgets('검수 중이어도 한도가 남았으면(can_submit) 단톡방 줄을 눌러 이어서 낸다', (tester) async {
      repository.tasks = Success([kakao(state: HeartTaskState.reviewing, canSubmit: true)]);
      await pump(tester);

      await tester.tap(find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.share));
      await tester.pumpAndSettle();

      expect(find.text('제출 /heart-tasks/submit/kakao_share'), findsOneWidget);
    });

    testWidgets('한도에 찬 줄(can_submit 아님)은 검수 중이어도 눌러지지 않는다', (tester) async {
      repository.tasks = Success([kakao(state: HeartTaskState.reviewing, canSubmit: false, used: 3)]);
      await pump(tester);

      await tester.tap(find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.share));
      await tester.pumpAndSettle();

      expect(find.textContaining('제출 /heart-tasks/submit'), findsNothing);
    });
  });

  group('반려 줄 사유 한 줄', () {
    const rewardOf = {HeartTaskKind.everytimePost: '40 · 월 1회', HeartTaskKind.kakaoShare: '25 · 월 3회'};

    /// 반려 줄 하나만 둔다(나머지는 pen 목록 그대로 검수중 · 완료 · 투표).
    void reject(HeartTaskKind kind, HeartTaskRejectReason? reason) {
      repository.tasks = Success([
        HeartTask(
          kind: kind,
          rewardHearts: kind == HeartTaskKind.everytimePost ? 40 : 25,
          state: HeartTaskState.rejected,
          used: 0,
          limit: kind == HeartTaskKind.everytimePost ? 1 : 3,
          rejectReason: reason,
        ),
        const HeartTask(kind: HeartTaskKind.pollVote, rewardHearts: 5, state: HeartTaskState.open, used: 0, limit: 3),
      ]);
    }

    for (final (reason, text) in [
      (HeartTaskRejectReason.dateMissing, '반려 · 날짜가 안 보여요'),
      (HeartTaskRejectReason.notVerified, '반려 · 게시글·공유가 확인되지 않아요'),
      (HeartTaskRejectReason.reused, '반려 · 이미 쓴 캡처예요'),
    ]) {
      testWidgets('에브리타임 반려 줄에 "$text" 가 보이고, 18b-2 의 사유 글자와 같은 문구다', (tester) async {
        reject(HeartTaskKind.everytimePost, reason);
        await pump(tester);

        expect(find.text(text), findsOneWidget);
        expect(text, '반려 · ${reason.label}');
      });
    }

    testWidgets('단톡방 반려 줄에도 사유가 붙는다(pen `x8OCS4` 두 번째 줄)', (tester) async {
      reject(HeartTaskKind.kakaoShare, HeartTaskRejectReason.notVerified);
      await pump(tester);

      final row = find.byType(HeartTaskRow).first;
      expect(find.descendant(of: row, matching: find.text('단톡방 공유')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('반려 · 게시글·공유가 확인되지 않아요')), findsOneWidget);
    });

    testWidgets('사유 줄은 반려 줄에만 있다 — 미완료 · 검수중 · 완료 · 사유 없는 반려에는 없다', (tester) async {
      await pump(tester);
      expect(find.textContaining('반려 ·'), findsNothing);
      expect(find.byKey(heartTaskRejectLineKey), findsNothing);

      repository.tasks = Success(sampleHeartTasks(everytime: HeartTaskState.open));
      await pump(tester);
      expect(find.textContaining('반려 ·'), findsNothing);

      reject(HeartTaskKind.everytimePost, null);
      await pump(tester);
      expect(find.textContaining('반려 ·'), findsNothing);
      expect(find.byKey(heartTaskRejectLineKey), findsNothing);
      expect(find.text('다시 제출'), findsOneWidget);
    });

    testWidgets('pen 높이 — 사유 있는 줄 328×72, 사유 없는 반려 줄 328×64', (tester) async {
      reject(HeartTaskKind.everytimePost, HeartTaskRejectReason.dateMissing);
      await pump(tester);
      expect(tester.getSize(find.byType(HeartTaskRow).first), const Size(328, 72)); // TW2ki 인스턴스 X4X2C · Ckrfi · Q6Olj

      reject(HeartTaskKind.everytimePost, null);
      await pump(tester);
      expect(tester.getSize(find.byType(HeartTaskRow).first), const Size(328, 64)); // 일반 줄
    });

    testWidgets('pen 사유 줄 — 아이콘 triangle-alert 12 error · 사이 4 · 글자 12/600 줄높이 1.3 error · 보상 줄 아래 2', (tester) async {
      reject(HeartTaskKind.everytimePost, HeartTaskRejectReason.dateMissing);
      await pump(tester);

      final line = find.byKey(heartTaskRejectLineKey);
      final icon = find.descendant(of: line, matching: find.byIcon(AppIcons.alertTriangle));
      final icon0 = tester.widget<Icon>(icon);
      expect((icon0.size, icon0.color), (12.0, AppColors.error)); // RiCqn
      expect(tester.getSize(icon), const Size(12, 12));

      final text = find.descendant(of: line, matching: find.text('반려 · 날짜가 안 보여요'));
      final style = tester.widget<Text>(text).style!;
      expect((style.fontSize, style.fontWeight, style.height, style.color), (12.0, FontWeight.w600, 1.3, AppColors.error)); // QiLmA
      expect(tester.getTopLeft(text).dx - tester.getTopRight(icon).dx, 4);
      expect(tester.getSize(text).height, closeTo(12 * 1.3, 0.5)); // 글자 상자는 올림되어 16
      // 1줄 폭 약 210 은 Pretendard 기준이라 시험 글꼴로는 재지 않는다 — 1줄에 들어가는지만 본다.
      expect(tester.getSize(text).height, lessThan(12 * 1.3 * 1.5));

      final title = find.descendant(of: find.byType(HeartTaskRow).first, matching: find.text('에브리타임 홍보'));
      expect(tester.getTopLeft(icon).dx, tester.getTopLeft(title).dx); // 같은 글 칸 왼쪽(MidCol)
      final reward = find.ancestor(of: find.text(rewardOf[HeartTaskKind.everytimePost]!), matching: find.byType(Row)).first;
      expect(tester.getTopLeft(line).dy - tester.getBottomLeft(reward).dy, 2);
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 배율 $scale — 긴 사유는 말줄임 없이 줄바꿈하고 줄이 자라며 넘치지 않는다', (tester) async {
        reject(HeartTaskKind.kakaoShare, HeartTaskRejectReason.notVerified);
        await pump(tester, textScale: scale);

        final text = find.text('반려 · 게시글·공유가 확인되지 않아요');
        final widget = tester.widget<Text>(text);
        expect((widget.maxLines, widget.overflow), (null, null));
        if (scale == 2.0) {
          expect(tester.getSize(text).height, greaterThan(12 * 1.3 * 2 * 1.5)); // 두 줄 이상
        }
        final row = tester.getRect(find.byType(HeartTaskRow).first);
        expect(tester.getRect(text).bottom, lessThanOrEqualTo(row.bottom));
        expect(row.height, greaterThanOrEqualTo(72));
        expect(tester.takeException(), isNull);
      });
    }

    // 글자가 두 줄이 돼도 아이콘은 첫 줄 옆에 붙어 있다(가운데로 내려가지 않는다). 1.0 배에서는 pen 처럼 첫 줄 가운데다.
    testWidgets('글자 배율 2.0 — 두 줄이 돼도 아이콘은 글자 첫 줄 위쪽에 붙는다', (tester) async {
      reject(HeartTaskKind.kakaoShare, HeartTaskRejectReason.notVerified);
      await pump(tester, textScale: 2);

      final line = find.byKey(heartTaskRejectLineKey);
      final icon = find.descendant(of: line, matching: find.byIcon(AppIcons.alertTriangle));
      final text = find.descendant(of: line, matching: find.text('반려 · 게시글·공유가 확인되지 않아요'));

      expect(tester.getSize(text).height, greaterThan(12 * 1.3 * 2 * 1.5)); // 두 줄 이상이어야 이 시험이 뜻이 있다
      expect(tester.getTopLeft(icon).dy - tester.getTopLeft(text).dy, closeTo(0, 2.5));
    });

    testWidgets('글자 배율 1.0 — 아이콘은 한 줄 글자의 세로 가운데(pen 그대로)', (tester) async {
      reject(HeartTaskKind.everytimePost, HeartTaskRejectReason.dateMissing);
      await pump(tester);

      final line = find.byKey(heartTaskRejectLineKey);
      final icon = find.descendant(of: line, matching: find.byIcon(AppIcons.alertTriangle));
      final text = find.descendant(of: line, matching: find.text('반려 · 날짜가 안 보여요'));

      expect(tester.getCenter(icon).dy, closeTo(tester.getCenter(text).dy, 0.6));
    });

    testWidgets('낭독 — 사유 글자가 읽히고 경고 아이콘이 따로 읽히지 않는다', (tester) async {
      final handle = tester.ensureSemantics();
      reject(HeartTaskKind.everytimePost, HeartTaskRejectReason.reused);
      await pump(tester);

      expect(find.bySemanticsLabel(RegExp('반려 · 이미 쓴 캡처예요')), findsOneWidget);
      final line = find.byKey(heartTaskRejectLineKey);
      expect(tester.widget<Icon>(find.descendant(of: line, matching: find.byIcon(AppIcons.alertTriangle))).semanticLabel, isNull);
      handle.dispose();
    });
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

  // 인증샷 여러 장(2026-10-19) — 18a 줄 아래 "검수 대기" 블록(pen pVxvl 대기 1건 제출 가능 · tYwTB 한도 찬 상태).
  // 단톡방은 검수 중이어도 월 3회 한도까지 이어 낸다: 줄 문구 "… · 이번 달 n회 남음" + [제출하기] 활성 / "… · 이번 달 한도 도달" + 비활성.
  group('검수 대기 블록과 단톡방 이어 제출(pen pVxvl · tYwTB)', () {
    final today = DateTime.now();
    DateTime at(int hour, int minute) => DateTime(today.year, today.month, today.day, hour, minute);
    HeartTaskPending queued(String id, DateTime createdAt, int photos) => HeartTaskPending(
          id: id,
          createdAt: createdAt,
          photoUrls: [for (var i = 0; i < photos; i++) 'https://signed.test/$id-$i'],
        );
    final everytimeWaiting = HeartTask(
      kind: HeartTaskKind.everytimePost,
      rewardHearts: 40,
      state: HeartTaskState.reviewing,
      used: 1,
      limit: 1,
      maxPhotos: 3,
      pending: [queued('e', at(14, 20), 3)],
    );
    // pen pVxvl: 대기 1 + 승인 1 → 이번 달 1회 남음.
    final kakaoOpen = HeartTask(
      kind: HeartTaskKind.kakaoShare,
      rewardHearts: 25,
      state: HeartTaskState.reviewing,
      used: 2,
      limit: 3,
      canSubmit: true,
      maxPhotos: 3,
      pending: [queued('k', at(14, 35), 2)],
    );
    // pen tYwTB: 승인 1 + 검수 2 → 한도 도달.
    final kakaoFull = HeartTask(
      kind: HeartTaskKind.kakaoShare,
      rewardHearts: 25,
      state: HeartTaskState.reviewing,
      used: 3,
      limit: 3,
      maxPhotos: 3,
      pending: [queued('k1', at(14, 35), 2), queued('k2', at(16, 2), 1)],
    );
    const poll = HeartTask(kind: HeartTaskKind.pollVote, rewardHearts: 5, state: HeartTaskState.open, used: 0, limit: 3);

    Finder chipOf(String label) => find.ancestor(of: find.text(label), matching: find.byType(ConstrainedBox)).first;
    BoxDecoration decorationOf(WidgetTester tester, String label) =>
        tester.widget<DecoratedBox>(find.ancestor(of: find.text(label), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;

    testWidgets('대기 1건 · 제출 가능 — 줄마다 "검수 대기 1건", 단톡방 문구 "이번 달 1회 남음", 칩은 "제출하기"(검수중 아님)', (tester) async {
      repository.tasks = Success([everytimeWaiting, kakaoOpen, poll]);
      await pump(tester);

      expect(find.text('검수 대기 1건'), findsNWidgets(2));
      expect(find.text('40 · 월 1회'), findsOneWidget);
      expect(find.text('25 · 월 3회 · 이번 달 1회 남음'), findsOneWidget);
      expect(find.text('제출하기'), findsOneWidget);
      expect(find.text('완료'), findsNothing);
      expect(find.text('인증하기'), findsNothing);
      // 검수중: 에브리타임 줄 칩 1 + 대기 블록 배지 2.
      expect(find.text('검수중'), findsNWidgets(3));
      expect(find.text('오늘 14:20 제출'), findsOneWidget);
      expect(find.text('오늘 14:35 제출'), findsOneWidget);
    });

    testWidgets('"제출하기" 칩은 84×28 · 14/600 ink · 바탕 E5E5E5(Action 인스턴스, 값표 pVxvl)', (tester) async {
      repository.tasks = Success([kakaoOpen]);
      await pump(tester);

      expect(tester.getSize(chipOf('제출하기')), const Size(84, 28));
      final style = tester.widget<Text>(find.text('제출하기')).style!;
      expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, AppColors.ink));
      expect(decorationOf(tester, '제출하기').color, AppColors.primaryDisabled);
    });

    testWidgets('검수 중이어도 한도가 남은 단톡방 줄을 누르면 18b 로 간다', (tester) async {
      repository.tasks = Success([everytimeWaiting, kakaoOpen, poll]);
      await pump(tester);

      await tester.tap(find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.share));
      await tester.pumpAndSettle();

      expect(find.text('제출 /heart-tasks/submit/kakao_share'), findsOneWidget);
    });

    testWidgets('에브리타임 대기 1건은 지금처럼 검수중 칩(누를 수 없음) + 대기 블록 1줄 — "제출하기" · "남음" 은 없다', (tester) async {
      repository.tasks = Success([everytimeWaiting]);
      await pump(tester);

      expect(find.text('검수중'), findsNWidgets(2));
      expect(find.text('제출하기'), findsNothing);
      expect(find.textContaining('이번 달'), findsNothing);
      expect(find.ancestor(of: find.text('에브리타임 홍보'), matching: find.byType(InkWell)), findsNothing);
    });

    testWidgets('블록은 줄 아래 8(줄 64 → 간격 8 → 블록), 왼쪽 40 안쪽, 다음 줄과 사이 8', (tester) async {
      repository.tasks = Success([everytimeWaiting, kakaoOpen, poll]);
      await pump(tester);

      final rows = find.byType(HeartTaskRow);
      final first = tester.getRect(rows.at(0));
      final block = tester.getRect(find.byType(HeartTaskPendingList).first);
      // 줄과 블록 사이 8 은 pen 이미지 실측(18a 줄 선 → 썸네일 위 ≈ 41 = 간격 8 + 블록 위 8 + 제목 17 + 8).
      expect(block.top - first.top, 64 + 8);
      expect(block.left - first.left, 0);
      expect(block.width, 328);
      expect(first.bottom, block.bottom);
      expect(tester.getRect(find.text('검수 대기 1건').first).left - first.left, 40);
      expect(tester.getTopLeft(rows.at(1)).dy - first.bottom, 8);
    });

    testWidgets('한도 도달 — "한도 도달" 문구 · 비활성 "제출하기"(F2F2F2 · 929292) · 대기 2건 · 안내 문구, 줄은 눌러지지 않는다', (tester) async {
      repository.tasks = Success([everytimeWaiting, kakaoFull, poll]);
      await pump(tester);

      expect(find.text('25 · 월 3회 · 이번 달 한도 도달'), findsOneWidget);
      expect(find.text('검수 대기 2건'), findsOneWidget);
      expect(find.text('이번 달 제출 3회를 모두 썼어요(승인 1건 · 검수 중 2건).'), findsOneWidget);
      expect(find.text('완료'), findsNothing);
      expect(tester.getSize(chipOf('제출하기')), const Size(84, 28));
      expect(decorationOf(tester, '제출하기').color, AppColors.surfaceStrong);
      expect(tester.widget<Text>(find.text('제출하기')).style!.color, AppColors.disabled);
      expect(find.ancestor(of: find.text('단톡방 공유'), matching: find.byType(InkWell)), findsNothing);

      await tester.tap(find.byWidgetPredicate((w) => w is Icon3d && w.icon == AppIcon3d.share));
      await tester.pumpAndSettle();
      expect(find.textContaining('제출 /heart-tasks/submit'), findsNothing);
    });

    testWidgets('낭독 — 한도 도달의 "제출하기" 는 비활성 버튼으로 읽힌다(눌러지는 척하지 않는다)', (tester) async {
      final handle = tester.ensureSemantics();
      repository.tasks = Success([kakaoFull]);
      await pump(tester);

      final data = tester.getSemantics(find.text('제출하기')).getSemanticsData();
      expect(data.label, '제출하기');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });

    testWidgets('한도가 남아도 대기가 없으면(승인만) 줄 문구는 지금 그대로 — "남음" 은 대기가 있을 때만', (tester) async {
      repository.tasks = const Success([
        HeartTask(kind: HeartTaskKind.kakaoShare, rewardHearts: 25, state: HeartTaskState.open, used: 1, limit: 3, canSubmit: true, maxPhotos: 3),
      ]);
      await pump(tester);

      expect(find.text('25 · 월 3회'), findsOneWidget);
      expect(find.text('인증하기'), findsOneWidget);
      expect(find.byType(HeartTaskPendingList), findsNothing);
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 배율 $scale — 대기 1건 · 한도 도달 모두 넘침 · 말줄임 없다', (tester) async {
        for (final tasks in [
          [everytimeWaiting, kakaoOpen, poll],
          [everytimeWaiting, kakaoFull, poll],
        ]) {
          repository.tasks = Success(tasks);
          await pump(tester, textScale: scale);

          expect(tester.takeException(), isNull);
          // 앱바 제목은 한 줄 말줄임이 원래 규칙이라 줄(HeartTaskRow)만 본다.
          final inRows = find.descendant(of: find.byType(HeartTaskRow), matching: find.byType(RichText));
          for (final paragraph in tester.renderObjectList<RenderParagraph>(inRows)) {
            expect(paragraph.didExceedMaxLines, isFalse, reason: paragraph.text.toPlainText());
          }
        }
      });
    }

    testWidgets('낭독 — 단톡방 줄이 "문구 + 제출하기" 로 읽히고, 대기 줄은 시각 · 장수 · 검수중이 한 덩어리다', (tester) async {
      final handle = tester.ensureSemantics();
      repository.tasks = Success([kakaoOpen]);
      await pump(tester);

      expect(find.bySemanticsLabel(RegExp('이번 달 1회 남음')), findsOneWidget);
      expect(find.bySemanticsLabel('오늘 14:35 제출, 사진 2장, 검수중'), findsOneWidget);
      handle.dispose();
    });
  });
}
