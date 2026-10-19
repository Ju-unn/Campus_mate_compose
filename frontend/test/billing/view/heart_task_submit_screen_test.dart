import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/image_compressor_provider.dart';
import 'package:campus_mate/billing/model/everytime_form_link.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/view/heart_task_photo_slots.dart';
import 'package:campus_mate/billing/view/heart_task_submit_screen.dart';
import 'package:campus_mate/billing/viewmodel/heart_task_submit_view_model.dart';
import 'package:campus_mate/billing/viewmodel/heart_tasks_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/muted_text_button.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../auth/model/fake_image_compressor.dart';
import '../model/fake_heart_task_repository.dart';
import 'pretendard.dart';

/// 무료 하트 인증 기준(사용자 결정 10-12 — pen 동기화 대기). 에브리타임은 옛 "날짜가 보이게 찍어 주세요" 를 합쳤다.
/// 단톡방 인원은 10-16 사용자 확정으로 5명 → 3명(앱 문구만 — 서버 · DB 는 인원을 검사하지 않는다).
const _everytimeCriteria = '앱 이름(CampusMate)이 들어간 홍보 글을 올리고, 올린 날짜가 보이게 찍어 주세요';
const _kakaoCriteria = '3명 이상이 있는 단톡방에 공유한 글과 단톡방 인원 수가 보이게 찍어 주세요';

/// 에브리타임 18b · 18b-2 의 보조 버튼(pen 18b `F15q0W` · 18b-2 `DMrAI` TextButton, 대장 전달 값 10-17).
const _formLabel = '에브리타임 양식 보기 →';

void main() {
  // 시험 기본 글꼴(Ahem)은 글자 폭이 실제와 달라 개수 줄("0/3장" + 힌트)이 접힌다 — 실제 글꼴로 pen 치수를 잰다.
  setUpAll(loadPretendard);
  late FakeHeartTaskRepository repository;
  // 없는 파일이어도 된다 — 위젯 테스트의 가짜 시계에서는 파일을 실제로 읽지 않는다.
  final photos = [File('proof1.jpg'), File('proof2.jpg'), File('proof3.jpg')];
  final photo = photos.first;
  // 갤러리가 돌려줄 사진 · 갤러리가 "몇 장 더 고르게 할까" 로 받은 값들.
  late List<File> nextPick;
  late List<int> asked;
  // 앱 안 브라우저로 연 주소(openUrlProvider — [open] 이 결과를 정한다)와 기기 브라우저로 연 주소(openExternalUrlProvider).
  late List<Uri> openedInApp;
  late List<Uri> openedExternal;
  late Future<bool> Function(Uri) open;

  setUp(() {
    repository = FakeHeartTaskRepository();
    nextPick = [photo];
    asked = [];
    openedInApp = [];
    openedExternal = [];
    open = (uri) async => true;
  });

  /// 18a 에서 들어온 것처럼 push 한다. 18c 는 글자만 있는 자리 화면.
  Future<GoRouter> pump(
    WidgetTester tester, {
    HeartTaskKind kind = HeartTaskKind.kakaoShare,
    HeartTaskRejectReason? reason,
    Size size = const Size(360, 780),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRoutes.heartTasks,
      routes: [
        GoRoute(path: AppRoutes.heartTasks, builder: (context, state) => const Text('18a')),
        GoRoute(
          path: '${AppRoutes.heartTaskSubmit}/:task',
          builder: (context, state) => HeartTaskSubmitScreen(kind: kind, rejectReason: reason),
        ),
        GoRoute(path: AppRoutes.heartTaskPending, builder: (context, state) => const Text('18c')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          heartTaskRepositoryProvider.overrideWithValue(repository),
          imageCompressorProvider.overrideWithValue(FakeImageCompressor()),
          openUrlProvider.overrideWithValue((uri) {
            openedInApp.add(uri);
            return open(uri);
          }),
          openExternalUrlProvider.overrideWithValue((uri) async {
            openedExternal.add(uri);
            return true;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    // 18a 가 떠 있는 채로 18b 로 들어온다 — 18a 가 읽어 둔 목록(항목의 max_photos)을 18b 가 따른다.
    final keepAlive = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).listen(heartTasksViewModelProvider, (_, _) {});
    addTearDown(keepAlive.close);
    await tester.pump();
    unawaited(router.push(heartTaskSubmitLocation(kind, reason)));
    await tester.pumpAndSettle();
    ProviderScope.containerOf(tester.element(find.byType(HeartTaskSubmitScreen)))
        .read(heartTaskSubmitViewModelProvider.notifier)
        .pickFromGallery = (remaining) async {
      asked.add(remaining);
      return nextPick.take(remaining).toList();
    };
    return router;
  }

  testWidgets('18b — 안내 · 단톡방 인증 기준 · 업로더 · 꺼진 "제출하기", 반려 알림 · 에브리타임 기준은 없다', (tester) async {
    await pump(tester);

    expect(find.text('인증샷 제출'), findsOneWidget);
    expect(find.text('스크린샷을 첨부하면 확인 후 하트를 드려요'), findsOneWidget);
    expect(find.text(_kakaoCriteria), findsOneWidget);
    // 옛 한 칸 업로더("스크린샷 첨부하기")는 사진 칸 3개로 바뀌었다(pen fUFvU · LgSoe).
    expect(find.text('스크린샷 첨부하기'), findsNothing);
    expect(find.text('0/3장'), findsOneWidget);
    expect(find.text('사진 추가'), findsNWidgets(3));
    expect(find.text(_everytimeCriteria), findsNothing);
    expect(find.textContaining('반려 사유'), findsNothing);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    expect(find.text('제출하기'), findsOneWidget);
  });

  testWidgets('에브리타임은 앱 이름 · 날짜 기준 한 덩어리 — 옛 "날짜가 보이게 찍어 주세요" 는 합쳐져 따로 없다', (tester) async {
    await pump(tester, kind: HeartTaskKind.everytimePost);

    expect(find.text(_everytimeCriteria), findsOneWidget);
    expect(find.text('날짜가 보이게 찍어 주세요'), findsNothing);
    expect(find.text(_kakaoCriteria), findsNothing);
  });

  for (final (kind, criteria) in [
    (HeartTaskKind.everytimePost, _everytimeCriteria),
    (HeartTaskKind.kakaoShare, _kakaoCriteria),
  ]) {
    testWidgets('${kind.code} 기준 — 12/400 muted 줄높이 1.4, 안내 → 4 → 기준 → 16 → 사진 블록(옛 업로더 자리 그대로)', (tester) async {
      await pump(tester, kind: kind);

      final text = find.text(criteria);
      final style = tester.widget<Text>(text).style!;
      expect((style.fontSize, style.fontWeight, style.height, style.color), (12, FontWeight.w400, 1.4, AppColors.muted));
      final guide = tester.getRect(find.text('스크린샷을 첨부하면 확인 후 하트를 드려요'));
      final rect = tester.getRect(text);
      expect(rect.top - guide.bottom, 4);
      expect(tester.getRect(find.byKey(heartTaskPhotoBlockKey)).top - rect.bottom, 16);
    });
  }

  testWidgets('18b-2 — 사유 알림과 "다시 제출하기", pen 배치 16 · 99 · 138 · 374', (tester) async {
    await pump(tester, reason: HeartTaskRejectReason.dateMissing);
    // 세로 좌표만 본다. 테스트 글꼴은 한글이 Pretendard 보다 넓어 안내(pen `qLG9R` 한 줄 264)가 360 폭에서 두 줄로
    // 접힌다 — 접히지 않게 화면만 넓힌다(home_screen_test 와 같다). 위젯에 말줄임을 달지 않는다(글자 확대 때 잘린다).
    tester.view.physicalSize = const Size(420, 780);
    await tester.pumpAndSettle();

    expect(find.text('반려 사유: 날짜가 안 보여요'), findsOneWidget);
    expect(find.text('다시 찍어 올려 주세요'), findsOneWidget);
    expect(find.text('다시 제출하기'), findsOneWidget);
    // 본문은 앱바(56) 아래에서 시작한다.
    const body = 56.0;
    final alert = find.ancestor(
      of: find.text('반려 사유: 날짜가 안 보여요'),
      matching: find.byWidgetPredicate((widget) => widget is Container && widget.color == AppColors.errorWash),
    );
    expect(tester.getRect(alert).top - body, 16);
    expect(tester.getRect(alert).height, 67);
    expect(tester.getRect(find.text('스크린샷을 첨부하면 확인 후 하트를 드려요')).top - body, 99);
    // pen 의 업로더 138 · 버튼 374 는 기준 캡션이 없을 때 값이다(사용자 결정 10-12 로 단톡방에도 캡션이 붙었다 — pen 동기화 대기).
    // 캡션 높이만큼만 내려가고 간격 규칙(안내 → 4 → 캡션 → 16 → 업로더 → 16 → 버튼)은 그대로다.
    final caption = tester.getRect(find.text(_kakaoCriteria));
    final block = tester.getRect(find.byKey(heartTaskPhotoBlockKey));
    expect(block.top - body, 138 + 4 + caption.height);
    // 사진 블록 = 개수 줄 20 + 간격 8 + 칸(pen uvkY2 · r7wOTV 104 — 본문 폭 328 에서. 이 시험은 화면을 420 으로 넓혔으니 칸은 (388 − 16) ÷ 3).
    expect(block.height, 20 + 8 + (420 - 32 - 16) / 3);
    expect(tester.getRect(find.byType(ElevatedButton)).top - block.bottom, 16);
  });

  testWidgets('사진을 고르면 버튼이 켜지고, 제출하면 18c 로 바뀌며 뒤로 가면 18a 다', (tester) async {
    final router = await pump(tester);

    await tester.tap(find.text('사진 추가').first);
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNotNull);
    await tester.tap(find.text('제출하기'));
    await tester.pumpAndSettle();

    expect(find.text('18c'), findsOneWidget);
    expect(repository.submitted, [(HeartTaskKind.kakaoShare, photo.path)]);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('18a'), findsOneWidget);
  });

  testWidgets('실패하면 버튼 위에 토스트로 알리고 화면에 남는다', (tester) async {
    repository.submitResult = const FailureResult(RateLimitedFailure());
    await pump(tester);

    await tester.tap(find.text('사진 추가').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('제출하기'));
    // 토스트 타이머는 프레임을 걸지 않아 pumpAndSettle 이 기다리지 않는다.
    await tester.pumpAndSettle();

    expect(find.text(heartTaskMonthlyLimitMessage), findsOneWidget);
    expect(find.text('18c'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(heartTaskMonthlyLimitMessage), findsNothing);
  });

  // 사진 칸 — 안내 묶음과 [제출하기] 사이, 옛 업로더(moNIO 220) 자리를 대체한다(값표: 사진 블록 uvkY2 3장 · r7wOTV 1장,
  // 18b 사진 3장 fUFvU · 1장 LgSoe). 첫 칸 "필수" 배지 마스터 fPA2r, 삭제 X 마스터 uzGT9, 빈 칸 마스터 jieCD.
  group('사진 칸', () {
    Finder addTiles() => find.byType(AddPhotoTile);
    Finder slot(int index) => find.byKey(heartTaskPhotoSlotKey(index));
    Finder remove(int index) => find.byKey(heartTaskPhotoRemoveKey(index));
    Finder circleOf(int index) =>
        find.descendant(of: remove(index), matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 28 && w.height == 28));

    /// 빈 칸을 한 번 눌러 [count] 장을 채운다(갤러리가 그만큼 돌려준다).
    Future<void> fill(WidgetTester tester, int count) async {
      nextPick = photos.take(count).toList();
      await tester.tap(addTiles().first);
      await tester.pumpAndSettle();
    }

    testWidgets('빈 칸 3개 — 각 104×104, 가로 간격 8(x16 · 128 · 240), 개수 줄 아래 8, "사진 추가" 14/600 primaryText', (tester) async {
      await pump(tester);

      expect(addTiles(), findsNWidgets(3));
      final rects = [for (var i = 0; i < 3; i++) tester.getRect(addTiles().at(i))];
      expect([for (final r in rects) r.size], const [Size(104, 104), Size(104, 104), Size(104, 104)]);
      expect([for (final r in rects) r.left], [16, 128, 240]);
      expect(rects.map((r) => r.top).toSet().length, 1);
      expect(rects.first.top - tester.getRect(find.text('0/3장')).bottom, 8);
      final label = tester.widget<Text>(find.text('사진 추가').first).style!;
      expect((label.fontSize, label.fontWeight, label.color), (14, FontWeight.w600, AppColors.primaryText));
    });

    testWidgets('개수 줄 — "n/3장" 14/600 ink + 힌트 12 muted, 가로 간격 8', (tester) async {
      await pump(tester);

      final count = tester.widget<Text>(find.text('0/3장')).style!;
      expect((count.fontSize, count.fontWeight, count.color), (14, FontWeight.w600, AppColors.ink));
      const hintText = '1장은 꼭 올려 주세요 · 최대 3장';
      final hint = tester.widget<Text>(find.text(hintText)).style!;
      expect((hint.fontSize, hint.color), (12, AppColors.muted));
      expect(tester.getRect(find.text(hintText)).left - tester.getRect(find.text('0/3장')).right, 8);
    });

    testWidgets('1장 — "1/3장", 첫 칸에 사진 · "필수" 배지(x4 y4) · X 28×28(오른쪽 위 4), 나머지 빈 칸 2개 · 제출하기 켜짐', (tester) async {
      await pump(tester);
      await fill(tester, 1);

      expect(find.text('1/3장'), findsOneWidget);
      expect(slot(0), findsOneWidget);
      expect(slot(1), findsNothing);
      expect(addTiles(), findsNWidgets(2));
      final tile = tester.getRect(slot(0));
      expect(tile.size, const Size(104, 104));
      expect(tester.widget<ClipRRect>(slot(0)).borderRadius, BorderRadius.circular(14));
      expect(tester.widget<Image>(find.descendant(of: slot(0), matching: find.byType(Image))).fit, BoxFit.cover);
      final badge = tester.getRect(find.ancestor(of: find.text('필수'), matching: find.byType(Container)).first);
      expect((badge.left - tile.left, badge.top - tile.top), (4, 4));
      final circle = tester.getRect(circleOf(0));
      expect((tile.right - circle.right, circle.top - tile.top), (4, 4));
      expect(circle.size, const Size(28, 28));
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNotNull);
    });

    testWidgets('3장 — "3/3장", 빈 칸 없음, X 3개, "필수" 배지는 첫 칸에만', (tester) async {
      await pump(tester);
      await fill(tester, 3);

      expect(find.text('3/3장'), findsOneWidget);
      expect(addTiles(), findsNothing);
      expect(find.text('사진 추가'), findsNothing);
      expect([for (var i = 0; i < 3; i++) tester.getRect(slot(i)).left], [16, 128, 240]);
      expect([for (var i = 0; i < 3; i++) remove(i).evaluate().length], [1, 1, 1]);
      expect(find.text('필수'), findsOneWidget);
      expect(find.descendant(of: slot(0), matching: find.text('필수')), findsOneWidget);
    });

    testWidgets('X 누름 영역은 44×44 이고 칸 모서리에 붙는다', (tester) async {
      await pump(tester);
      await fill(tester, 1);

      final hit = tester.getRect(remove(0));
      final tile = tester.getRect(slot(0));
      expect(hit.size, const Size(44, 44));
      expect((hit.right, hit.top), (tile.right, tile.top));
    });

    testWidgets('빈 칸을 누르면 남은 장수만큼 고르게 한다 — 0장이면 3, 1장이면 2', (tester) async {
      await pump(tester);

      await fill(tester, 1);
      nextPick = [photos[1], photos[2]];
      await tester.tap(addTiles().first);
      await tester.pumpAndSettle();

      expect(asked, [3, 2]);
      expect(find.text('3/3장'), findsOneWidget);
    });

    testWidgets('X 를 누르면 그 장만 빠지고 순서가 이어진다 — 다 빼면 제출하기가 꺼진다', (tester) async {
      await pump(tester);
      await fill(tester, 3);

      await tester.tap(remove(1));
      await tester.pumpAndSettle();
      expect(find.text('2/3장'), findsOneWidget);
      expect(slot(1), findsOneWidget);
      expect(slot(2), findsNothing);
      expect(addTiles(), findsOneWidget);

      await tester.tap(remove(1));
      await tester.pumpAndSettle();
      await tester.tap(remove(0));
      await tester.pumpAndSettle();
      expect(find.text('0/3장'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    });

    testWidgets('제출하면 고른 순서대로 사진 전부를 보낸다', (tester) async {
      await pump(tester);
      await fill(tester, 3);

      await tester.tap(find.text('제출하기'));
      await tester.pumpAndSettle();

      expect(repository.submitted, [(HeartTaskKind.kakaoShare, 'proof1.jpg,proof2.jpg,proof3.jpg')]);
      expect(find.text('18c'), findsOneWidget);
    });

    testWidgets('옛 서버(max_photos 1) — 칸 1개 · "0/1장" · "최대 1장", 한 장만 고르게 한다', (tester) async {
      repository.tasks = const Success([
        HeartTask(kind: HeartTaskKind.kakaoShare, rewardHearts: 25, state: HeartTaskState.open, used: 0, limit: 3, canSubmit: true, maxPhotos: 1),
      ]);
      await pump(tester);

      expect(addTiles(), findsOneWidget);
      expect(tester.getSize(addTiles()), const Size(104, 104));
      expect(find.text('0/1장'), findsOneWidget);
      expect(find.text('1장은 꼭 올려 주세요 · 최대 1장'), findsOneWidget);
      nextPick = photos;
      await tester.tap(addTiles());
      await tester.pumpAndSettle();
      expect(asked, [1]);
      expect(find.text('1/1장'), findsOneWidget);
      expect(addTiles(), findsNothing);
    });

    for (final (kind, reason) in [
      (HeartTaskKind.everytimePost, null),
      (HeartTaskKind.everytimePost, HeartTaskRejectReason.dateMissing),
      (HeartTaskKind.kakaoShare, HeartTaskRejectReason.reused),
    ]) {
      testWidgets('${kind.code} 반려 $reason — 같은 사진 칸(에브리타임 · 18b-2 도 같은 블록)', (tester) async {
        await pump(tester, kind: kind, reason: reason);

        expect(addTiles(), findsNWidgets(3));
        expect(find.text('0/3장'), findsOneWidget);
        expect(tester.getSize(find.byKey(heartTaskPhotoBlockKey)), const Size(328, 132));
      });
    }

    testWidgets('빈 칸 잉크는 칸 자신의 Material 이 그린다(COMMON §4-2)', (tester) async {
      await pump(tester);

      final tile = find.descendant(of: addTiles().first, matching: find.byType(InkWell));
      final painter = find.ancestor(of: tile, matching: find.byType(Material)).first;
      expect(tester.getSize(painter), tester.getSize(tile));
      expect(tester.getSize(painter), const Size(104, 104));
    });

    for (final scale in [1.3, 2.0]) {
      for (final count in [0, 1, 3]) {
        testWidgets('글자 배율 $scale · $count장 — 넘침 · 말줄임 없고 누름 영역이 44 이상이다', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pump(tester, size: const Size(360, 900));
          if (count > 0) await fill(tester, count);

          expect(tester.takeException(), isNull);
          for (final paragraph in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
            expect(paragraph.didExceedMaxLines, isFalse, reason: paragraph.text.toPlainText());
          }
          for (var i = 0; i < 3 - count; i++) {
            expect(tester.getSize(addTiles().at(i)).shortestSide, greaterThanOrEqualTo(44));
          }
          for (var i = 0; i < count; i++) {
            expect(tester.getSize(remove(i)).shortestSide, greaterThanOrEqualTo(44));
          }
          // 칸은 글자가 커져도 104 그대로 — 개수 줄만 자란다(칸이 안 찌그러진다).
          if (count < 3) expect(tester.getSize(addTiles().first), const Size(104, 104));
        });
      }
    }

    testWidgets('낭독 — 개수 · 칸 번호 · 필수 · 빼기 버튼 · 빈 칸 버튼', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await fill(tester, 1);

      expect(find.bySemanticsLabel('사진 3장 중 1장'), findsOneWidget);
      expect(find.bySemanticsLabel('사진 1, 필수'), findsOneWidget);
      final removeData = tester.getSemantics(remove(0)).getSemanticsData();
      expect(removeData.label, '사진 1 빼기');
      expect(removeData.flagsCollection.isButton, isTrue);
      expect(removeData.hasAction(SemanticsAction.tap), isTrue);
      // 배지의 "필수" 는 칸 이름이 이미 읽어 주므로 따로 읽지 않는다.
      expect(find.bySemanticsLabel('필수'), findsNothing);
      final add = tester.getSemantics(addTiles().first).getSemanticsData();
      expect(add.flagsCollection.isButton, isTrue);
      expect(add.label, contains('사진 추가'));
      handle.dispose();
    });
  });

  for (final (kind, criteria) in [
    (HeartTaskKind.everytimePost, _everytimeCriteria),
    (HeartTaskKind.kakaoShare, _kakaoCriteria),
  ]) {
    testWidgets('${kind.code} — 글자 2배에서도 넘침 예외가 없고 말줄임으로 잘린 글자도 없다(기준 캡션 포함)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, kind: kind, reason: HeartTaskRejectReason.notVerified);

      expect(tester.takeException(), isNull);
      expect(find.text(criteria), findsOneWidget);
      // 넘침 예외가 없어도 maxLines 로 조용히 잘릴 수 있다(DESIGN §11.2) — 화면 글자를 전부 본다.
      for (final paragraph in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
        expect(paragraph.didExceedMaxLines, isFalse, reason: paragraph.text.toPlainText());
      }
      // 캡션 아래 간격 규칙도 2배에서 그대로다.
      expect(tester.getRect(find.byKey(heartTaskPhotoBlockKey)).top - tester.getRect(find.text(criteria)).bottom, 16);
    });
  }

  group('에브리타임 양식 보기(pen `F15q0W` · `DMrAI` TextButton)', () {
    Finder formButton() => find.widgetWithText(MutedTextButton, _formLabel);

    testWidgets('에브리타임 18b 에만 있다 — 단톡방 18b 에는 없다', (tester) async {
      await pump(tester, kind: HeartTaskKind.everytimePost);
      expect(formButton(), findsOneWidget);

      await pump(tester);
      expect(find.text(_formLabel), findsNothing);
    });

    testWidgets('반려 뒤 다시 내는 에브리타임 18b-2 에도 있다', (tester) async {
      await pump(tester, kind: HeartTaskKind.everytimePost, reason: HeartTaskRejectReason.dateMissing);

      expect(find.text('반려 사유: 날짜가 안 보여요'), findsOneWidget);
      expect(formButton(), findsOneWidget);
    });

    for (final reason in [null, HeartTaskRejectReason.dateMissing]) {
      testWidgets('사진 블록 → 16 → 버튼 328×48(본문 폭) → 16 → 제출 버튼, 14/600 muted 가운데(반려 $reason)', (tester) async {
        await pump(tester, kind: HeartTaskKind.everytimePost, reason: reason);

        final uploader = tester.getRect(find.byKey(heartTaskPhotoBlockKey));
        final button = tester.getRect(formButton());
        final submit = tester.getRect(find.byType(ElevatedButton));
        expect(button.top - uploader.bottom, 16);
        expect(submit.top - button.bottom, 16);
        expect(button.size, const Size(328, 48));
        expect(button.left, uploader.left);
        expect(tester.getCenter(find.text(_formLabel)).dx, closeTo(button.center.dx, 0.01));
        final style = tester.widget<Text>(find.text(_formLabel)).style!;
        expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, AppColors.muted));
      });
    }

    testWidgets('누르면 양식 노션 주소를 앱 안 브라우저(openUrlProvider)로 연다 — 기기 브라우저는 0번(10-16 사용자 결정)', (tester) async {
      await pump(tester, kind: HeartTaskKind.everytimePost);

      await tester.tap(formButton());
      await tester.pump();

      expect(openedInApp, [everytimeFormLink]);
      expect(openedExternal, isEmpty);
      expect(find.text(const UnknownFailure().toDisplayMessage()), findsNothing);
    });

    testWidgets('여는 호출이 끝나기 전에 다시 눌러도 한 번만 연다', (tester) async {
      final pending = Completer<bool>();
      open = (uri) => pending.future;
      await pump(tester, kind: HeartTaskKind.everytimePost);

      await tester.tap(formButton());
      await tester.tap(formButton());
      await tester.pump();
      expect(openedInApp, [everytimeFormLink]);

      pending.complete(true);
      await tester.pump();
      await tester.tap(formButton());
      await tester.pump();
      expect(openedInApp, [everytimeFormLink, everytimeFormLink]);
    });

    // openInApp 은 연 것 · 사용자가 닫은 것을 true, 예외를 false 로 돌려준다(open_url.dart:18-30) — false 가 "못 열었다".
    // 예외는 provider 를 바꿔 끼울 때를 위한 방어다(설정 16 · 결제 안내와 같다).
    testWidgets('열지 못하면(false · 예외) 실패 토스트를 3초 띄운다', (tester) async {
      for (final throws in [false, true]) {
        open = (uri) async {
          if (throws) throw StateError('기기 쪽 오류');
          return false;
        };
        await pump(tester, kind: HeartTaskKind.everytimePost);

        await tester.tap(formButton());
        await tester.pump();

        expect(find.text(const UnknownFailure().toDisplayMessage()), findsOneWidget, reason: 'throws=$throws');
        await tester.pump(const Duration(seconds: 3));
        expect(find.text(const UnknownFailure().toDisplayMessage()), findsNothing, reason: 'throws=$throws');
      }
    });

    testWidgets('낭독기 — "에브리타임 양식 보기, 브라우저로 열려요" 버튼으로 읽고(화살표는 읽지 않는다) 누를 수 있다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, kind: HeartTaskKind.everytimePost);

      final data = tester.getSemantics(formButton()).getSemanticsData();
      expect(data.label, '에브리타임 양식 보기, 브라우저로 열려요');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    for (final reason in [null, HeartTaskRejectReason.notVerified]) {
      testWidgets('작은 화면 360×640 · 글자 2배 — 넘침 · 말줄임 없고, 스크롤하면 제출 버튼이 다 보인다(반려 $reason)', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pump(tester, kind: HeartTaskKind.everytimePost, reason: reason, size: const Size(360, 640));

        expect(tester.takeException(), isNull);
        for (final paragraph in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
          expect(paragraph.didExceedMaxLines, isFalse, reason: paragraph.text.toPlainText());
        }
        // ListView 는 화면 밖 칸을 아직 만들지 않는다 — 제출 버튼까지 내린 뒤 잰다.
        final submit = find.byType(ElevatedButton);
        await tester.scrollUntilVisible(submit, 100, scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        final viewport = tester.getRect(find.byType(Scrollable).first);
        final rect = tester.getRect(submit);
        expect(rect.top, greaterThanOrEqualTo(viewport.top));
        expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
        // 글자를 키우면 버튼도 따라 커지고(최소 48) 제출 버튼을 덮지 않는다.
        final button = tester.getRect(formButton());
        expect(button.height, greaterThanOrEqualTo(48));
        expect(rect.top - button.bottom, 16);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
