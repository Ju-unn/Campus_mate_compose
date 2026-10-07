import 'dart:async';
import 'dart:io';

import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/view/heart_bundle_card.dart';
import 'package:campus_mate/billing/view/heart_purchase_bar.dart';
import 'package:campus_mate/billing/view/heart_store_screen.dart';
import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../me/model/fake_me_repository.dart';
import '../model/fake_heart_task_repository.dart';

/// 이름·학교는 지어낸 값이다.
MyProfile _profile(int hearts) => MyProfile(
  nickname: '여우',
  age: 23,
  university: '가나대학교',
  major: '경영학과',
  heightCm: 178,
  mbti: 'ENFP',
  avatarUrl: null,
  photos: const [],
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: 165,
  preferredHeightMax: 180,
  bio: '',
  heartBalance: hearts,
  avatarRegenCost: 10,
);

/// 읽기가 [release] 될 때까지 멈춰 있는 가짜 저장소 — "읽는 중" 모양을 본다.
class _SlowTaskRepository extends FakeHeartTaskRepository {
  final Completer<void> release = Completer<void>();

  @override
  Future<Result<List<HeartTask>>> fetchTasks() async {
    await release.future;
    return super.fetchTasks();
  }
}

/// 시험 기본 글꼴(Ahem)은 글자마다 폭이 같은 네모라 카드 안 폭이 실제와 전혀 다르다 — 실제 글꼴 Pretendard 를 불러 pen 치수로 잰다.
Future<void> _loadPretendard() async {
  final loader = FontLoader('Pretendard');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(
      File('assets/fonts/Pretendard-$weight.otf').readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(_loadPretendard);
  late FakeHeartTaskRepository tasks;
  setUp(() => tasks = FakeHeartTaskRepository());

  /// 설정에서 들어온 것처럼 한 번 push 한다 — 뒤로 버튼이 보이게. 화면이 길어 스크롤 없이 다 그리도록 키를 크게 잡는다.
  Future<void> pump(
    WidgetTester tester, {
    Result<MyProfile>? profile,
    double textScale = 1,
    double height = 1700,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (context, state) => const Text('설정')),
        GoRoute(path: AppRoutes.heartStore, builder: (context, state) => const HeartStoreScreen()),
        GoRoute(path: AppRoutes.faq, builder: (context, state) => const Text('21 자주 묻는 질문')),
        GoRoute(path: AppRoutes.community, builder: (context, state) => const Text('커뮤니티')),
        GoRoute(path: '${AppRoutes.heartTaskSubmit}/:task', builder: (context, state) => Text('제출 ${state.uri}')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          heartTaskRepositoryProvider.overrideWithValue(tasks),
          meRepositoryProvider.overrideWithValue(FakeMeRepository(profile ?? Success(_profile(320)))),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    unawaited(router.push(AppRoutes.heartStore));
    if (settle) await tester.pumpAndSettle();
  }

  Finder cardOf(int hearts) => find.widgetWithText(HeartBundleCard, '$hearts하트');

  /// 카드가 칠한 바탕 · 테두리.
  (Color?, Color?, double?) paint(WidgetTester tester, int hearts) {
    final card = cardOf(hearts);
    final material = tester.widget<Material>(find.descendant(of: card, matching: find.byType(Material)).first);
    final border =
        tester
                .widget<Container>(find.descendant(of: card, matching: find.byType(Container)).first)
                .foregroundDecoration!
            as BoxDecoration;
    final side = (border.border! as Border).top;
    return (material.color, side.color, side.width);
  }

  group('틀(pen `IAy1j`)', () {
    testWidgets('앱바 `RRpV8` — 뒤로 48 (12,4), 제목 "하트" 18/700, 오른쪽 3D 도움말 24 (누름 48, x300)', (tester) async {
      await pump(tester);

      expect(find.text('하트'), findsWidgets);
      final title = tester.widget<Text>(find.descendant(of: find.byType(AppBar), matching: find.text('하트'))).style!;
      expect((title.fontSize, title.fontWeight, title.color), (18, FontWeight.w700, AppColors.ink));
      final back = find.byTooltip('Back');
      expect(tester.getRect(back), const Rect.fromLTWH(12, 4, 48, 48));
      expect(tester.getTopLeft(find.descendant(of: find.byType(AppBar), matching: find.text('하트'))).dx, 64);
      expect(tester.getRect(find.byTooltip('도움말').first), const Rect.fromLTWH(300, 4, 48, 48));
      final help = tester.widget<Icon3d>(
        find.descendant(of: find.byTooltip('도움말').first, matching: find.byType(Icon3d)),
      );
      expect((help.icon, help.size), (AppIcon3d.help, 24));
    });

    testWidgets('히어로 `LbUx1` 180×180 가운데(x90) · 보유 하트 `p9CUb` 는 서버 값 "320개"', (tester) async {
      await pump(tester);

      final hero = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/images/heart-value-scene.png',
      );
      expect(tester.getRect(hero), const Rect.fromLTWH(90, 56 + 8, 180, 180));
      expect(find.text('보유 하트'), findsOneWidget);
      final amount = tester.widget<Text>(find.text('320개')).style!;
      expect((amount.fontSize, amount.fontWeight, amount.color), (32, FontWeight.w700, AppColors.ink));
    });

    testWidgets('보유 하트는 서버 값이 바뀌면 그대로 따라가고 1,000 이상은 쉼표', (tester) async {
      await pump(tester, profile: Success(_profile(12480)));

      expect(find.text('12,480개'), findsOneWidget);
    });

    testWidgets('보유 하트를 못 읽으면 숫자 자리는 "-"(pen 에 없는 상태)', (tester) async {
      await pump(tester, profile: const FailureResult(NetworkFailure()));

      expect(find.text('-개'), findsNothing);
      expect(find.text('-'), findsOneWidget);
    });

    testWidgets('섹션 제목 "구매하기" · "무료로 모으기" 20/600 ink, 구매 안내 박스는 #F7F7F7', (tester) async {
      await pump(tester);

      for (final label in ['구매하기', '무료로 모으기']) {
        final style = tester.widget<Text>(find.text(label)).style!;
        expect((style.fontSize, style.fontWeight, style.color), (20, FontWeight.w600, AppColors.ink), reason: label);
      }
      expect(find.text('추가 카드는 다음 카드가 올 때까지 한 장만 열 수 있어요. 산 카드는 결정할 때까지 사라지지 않아요.'), findsOneWidget);
    });
  });

  group('번들 카드(pen `w0vIYG`)', () {
    testWidgets('328×88 다섯 장이 사이 16 으로 이어진다', (tester) async {
      await pump(tester);

      final cards = find.byType(HeartBundleCard);
      expect(cards, findsNWidgets(5));
      for (var i = 0; i < 5; i++) {
        expect(tester.getSize(cards.at(i)), const Size(328, 88), reason: '$i번째');
        if (i > 0) expect(tester.getTopLeft(cards.at(i)).dy - tester.getBottomLeft(cards.at(i - 1)).dy, 16);
      }
    });

    testWidgets('글자: 수량 · 가격 · 원가 · 할인율 · "최대 할인"(800 만) · "추천"(100 만)', (tester) async {
      await pump(tester);

      for (final text in [
        '50하트',
        '3,000원',
        '5,700원',
        '원가',
        '6,000원',
        '5%',
        '10,800원',
        '12,000원',
        '10%',
        '20,400원',
        '24,000원',
        '15%',
        '38,400원',
        '48,000원',
        '20%',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.text('최대 할인'), findsOneWidget);
      expect(find.descendant(of: cardOf(800), matching: find.text('최대 할인')), findsOneWidget);
      expect(find.text('추천'), findsNWidgets(2)); // 카드 태그 하나 + 하단 구매바 캡션 하나
      expect(find.descendant(of: cardOf(100), matching: find.text('추천')), findsOneWidget);
      final original = tester.widget<Text>(find.descendant(of: cardOf(100), matching: find.text('6,000원'))).style!;
      expect(original.decoration, TextDecoration.lineThrough);
      expect(find.descendant(of: cardOf(50), matching: find.text('원가')), findsNothing);
    });

    testWidgets('처음엔 100하트가 선택 — 바탕 #FFF0F2 · 테두리 2px primary, 나머지는 흰 바탕 · 1px #EBEBEB', (tester) async {
      await pump(tester);

      expect(paint(tester, 100), (AppColors.primaryWash, AppColors.primary, 2.0));
      for (final hearts in [50, 200, 400, 800]) {
        expect(paint(tester, hearts), (AppColors.canvas, AppColors.hairlineSoft, 1.0), reason: '$hearts');
      }
    });

    testWidgets('추천 태그 `Fs0PO` — 카드 위 끝에 걸친다(x16 · y−9, 높이 18)', (tester) async {
      await pump(tester);

      final tag = find.descendant(of: cardOf(100), matching: find.text('추천'));
      final box = find.ancestor(of: tag, matching: find.byType(Container)).first;
      final card = tester.getRect(cardOf(100));
      expect(tester.getTopLeft(box) - card.topLeft, const Offset(16, -9));
      expect(tester.getSize(box).height, 18);
    });

    testWidgets('카드를 누르면 선택만 바뀌고, 안 눌린 카드 안의 글자는 움직이지 않는다', (tester) async {
      await pump(tester);
      final before = tester.getTopLeft(find.descendant(of: cardOf(200), matching: find.text('200하트')));

      await tester.tap(cardOf(200));
      await tester.pump();

      expect(paint(tester, 200), (AppColors.primaryWash, AppColors.primary, 2.0));
      expect(paint(tester, 100), (AppColors.canvas, AppColors.hairlineSoft, 1.0));
      expect(tester.getTopLeft(find.descendant(of: cardOf(200), matching: find.text('200하트'))), before);
      expect(find.byType(BottomSheet), findsNothing); // 카드를 눌러도 시트는 안 열린다
    });

    testWidgets('낭독은 카드마다 한 번 — 수량 · 가격 · 할인 · 추천, 고른 카드는 selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel('100하트, 5,700원, 5퍼센트 할인, 추천'), findsOneWidget);
      expect(find.bySemanticsLabel('800하트, 38,400원, 20퍼센트 할인, 최대 할인'), findsOneWidget);
      expect(find.bySemanticsLabel('50하트, 3,000원'), findsOneWidget);
      handle.dispose();
    });
  });

  group('하단 구매바(pen `GG0ei`)', () {
    testWidgets('360×88, 고른 번들 이름 · 추천 캡션 · 회색 "곧 열려요" 버튼 96×52 (x248,y12)', (tester) async {
      await pump(tester);

      final bar = find.byType(HeartPurchaseBar);
      expect(tester.getSize(bar), const Size(360, 88));
      expect(tester.getTopLeft(bar).dy, 1700 - 88);
      final name = find.descendant(of: bar, matching: find.text('100하트'));
      expect(name, findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('추천')), findsOneWidget);
      final button = find.descendant(of: bar, matching: find.text('곧 열려요'));
      final fill = tester.widget<Material>(find.ancestor(of: button, matching: find.byType(Material)).first);
      expect(fill.color, AppColors.primaryDisabled);
      expect(tester.widget<Text>(button).style!.color, AppColors.disabled);
      final rect = tester.getRect(find.ancestor(of: button, matching: find.byType(InkWell)).first);
      expect((rect.height, rect.right, rect.top - tester.getTopLeft(bar).dy), (52, 344, 12));
    });

    testWidgets('다른 번들을 고르면 이름이 바뀌고, 추천이 아니면 캡션이 사라진다', (tester) async {
      await pump(tester);

      await tester.tap(cardOf(400));
      await tester.pump();

      final bar = find.byType(HeartPurchaseBar);
      expect(find.descendant(of: bar, matching: find.text('400하트')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('추천')), findsNothing);
    });
  });

  group('구매 확인 시트(pen `jqXSU` 18d)', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.descendant(of: find.byType(HeartPurchaseBar), matching: find.text('곧 열려요')));
      await tester.pumpAndSettle();
    }

    testWidgets('하단 버튼이 연다 — 제목 · 고른 상품 · 안내 · 회색 "곧 열려요" · 취소', (tester) async {
      await pump(tester);

      await openSheet(tester);

      expect(find.text('하트를 구매할까요?'), findsOneWidget);
      expect(find.text('100하트 · 5,700원'), findsOneWidget);
      expect(find.text('추가 카드는 다음 카드가 올 때까지 한 장만 열 수 있어요. 산 카드는 결정할 때까지 사라지지 않아요.'), findsNWidgets(2));
      expect(find.text('취소'), findsOneWidget);
      final title = tester.widget<Text>(find.text('하트를 구매할까요?')).style!;
      expect((title.fontSize, title.fontWeight), (24, FontWeight.w700));
    });

    testWidgets('시트 버튼 둘 — 328×52 모서리 14, 구매는 회색 글자 #929292, 취소 `KAUyy` 는 같은 #E5E5E5 채움에 글자 #222222 16/700', (
      tester,
    ) async {
      await pump(tester);
      await openSheet(tester);

      for (final (label, color) in [('곧 열려요', AppColors.disabled), ('취소', AppColors.ink)]) {
        final text = find.descendant(of: find.byType(BottomSheet), matching: find.text(label));
        final style = tester.widget<Text>(text).style!;
        expect((style.fontSize, style.fontWeight, style.color), (16, FontWeight.w700, color), reason: label);
        final material = tester.widget<Material>(find.ancestor(of: text, matching: find.byType(Material)).first);
        expect(
          (material.color, material.borderRadius),
          (AppColors.primaryDisabled, BorderRadius.circular(14)),
          reason: label,
        );
        expect(
          tester.getSize(find.ancestor(of: text, matching: find.byType(InkWell)).first),
          const Size(328, 52),
          reason: label,
        );
      }
    });

    testWidgets('카드 안 수량 · 할인 · 가격 사이는 12', (tester) async {
      await pump(tester);

      final card = cardOf(100);
      final discount = tester.getRect(find.descendant(of: card, matching: find.text('5%')));
      final price = tester.getRect(find.descendant(of: card, matching: find.text('5,700원')));
      final original = tester.getRect(find.descendant(of: card, matching: find.text('6,000원')));
      expect(price.left - discount.right, greaterThanOrEqualTo(12));
      expect(
        tester.getRect(card).right - 16,
        closeTo(price.right > original.right ? price.right : original.right, 0.5),
      );
    });

    testWidgets('고른 번들이 바뀌면 시트의 상품도 바뀐다', (tester) async {
      await pump(tester);
      await tester.tap(cardOf(800));
      await tester.pump();

      await openSheet(tester);

      expect(find.text('800하트 · 38,400원'), findsOneWidget);
    });

    testWidgets('"취소" 는 닫기만 한다 — 안내 토스트 없음', (tester) async {
      await pump(tester);
      await openSheet(tester);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(find.text('하트를 구매할까요?'), findsNothing);
      expect(find.byType(AppToast), findsNothing);
    });

    testWidgets('시트의 회색 "곧 열려요" 를 누르면 시트가 닫히고 토스트만 뜬다(2초 뒤 사라짐), 결제는 없다', (tester) async {
      await pump(tester);
      await openSheet(tester);

      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('곧 열려요')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.text('하트를 구매할까요?'), findsNothing);
      expect(find.byType(AppToast), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(AppToast), findsNothing);
    });

    testWidgets('제목줄 도움말은 시트를 닫고 하트·결제 FAQ 로 간다', (tester) async {
      await pump(tester);
      await openSheet(tester);

      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.byTooltip('도움말')));
      await tester.pumpAndSettle();

      expect(find.text('21 자주 묻는 질문'), findsOneWidget);
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 배율 $scale 에서도 시트가 넘치지 않고 모든 버튼에 닿는다', (tester) async {
        await pump(tester, textScale: scale, height: 700);
        await tester.tap(find.descendant(of: find.byType(HeartPurchaseBar), matching: find.text('곧 열려요')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('취소'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('취소'), findsOneWidget);
      });
    }

    testWidgets('앱바의 도움말도 FAQ 로 간다', (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip('도움말').first);
      await tester.pumpAndSettle();

      expect(find.text('21 자주 묻는 질문'), findsOneWidget);
    });
  });

  group('무료로 모으기(18a 와 같은 줄)', () {
    testWidgets('서버 목록 세 줄을 기존 HeartTaskRow 로 그린다 — 328×64, 사이 4', (tester) async {
      await pump(tester);

      final rows = find.byType(HeartTaskRow);
      expect(rows, findsNWidgets(3));
      expect(find.text('에브리타임 홍보'), findsOneWidget);
      expect(find.text('학교 단톡방 공유'), findsOneWidget);
      expect(find.text('커뮤니티 투표'), findsOneWidget);
      expect(tester.getSize(rows.at(0)), const Size(328, 64));
      expect(tester.getTopLeft(rows.at(1)).dy - tester.getBottomLeft(rows.at(0)).dy, 4);
      expect(find.text('초기 보상 기준 · 인증 후 지급\n100명 이후 홍보 30 / 단톡방 20 하트'), findsOneWidget);
    });

    testWidgets('투표 미완료 줄을 누르면 커뮤니티로, 인증 미완료 줄을 누르면 제출(18b)로 간다', (tester) async {
      tasks.tasks = Success(sampleHeartTasks(everytime: HeartTaskState.open));
      await pump(tester);

      await tester.tap(find.text('에브리타임 홍보'));
      await tester.pumpAndSettle();
      expect(find.textContaining('제출 /heart-tasks/submit/everytime_post'), findsOneWidget);
    });

    testWidgets('투표 줄 → 커뮤니티 탭', (tester) async {
      await pump(tester);

      await tester.tap(find.text('커뮤니티 투표'));
      await tester.pumpAndSettle();

      expect(find.text('커뮤니티'), findsOneWidget);
    });

    testWidgets('읽는 중에는 섹션에만 도는 표시가 있고 번들은 바로 보인다(pen 에 없는 상태)', (tester) async {
      final slow = _SlowTaskRepository();
      tasks = slow;
      await pump(tester, settle: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(HeartBundleCard), findsNWidgets(5));
      expect(find.byType(HeartTaskRow), findsNothing);
      slow.release.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HeartTaskRow), findsNWidgets(3));
    });

    testWidgets('읽기에 실패하면 섹션에만 문구 + "다시 시도", 누르면 다시 읽는다(pen 에 없는 상태)', (tester) async {
      tasks.tasks = const FailureResult(NetworkFailure());
      await pump(tester);

      expect(find.byType(HeartTaskRow), findsNothing);
      expect(find.byType(HeartBundleCard), findsNWidgets(5));
      expect(find.text('다시 시도'), findsOneWidget);
      final asked = tasks.fetchCount;
      tasks.tasks = Success(sampleHeartTasks());

      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(tasks.fetchCount, asked + 1);
      expect(find.byType(HeartTaskRow), findsNWidgets(3));
    });
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서도 넘침 오류가 없고 카드 높이는 88 이상이다(스크롤 끝까지)', (tester) async {
      await pump(tester, textScale: scale, height: 780);

      for (final hearts in [50, 100, 200, 400, 800]) {
        await tester.ensureVisible(cardOf(hearts));
        await tester.pump();
        expect(tester.getSize(cardOf(hearts)).height, greaterThanOrEqualTo(88), reason: '$hearts');
        expect(tester.getSize(cardOf(hearts)).width, 328, reason: '$hearts');
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
