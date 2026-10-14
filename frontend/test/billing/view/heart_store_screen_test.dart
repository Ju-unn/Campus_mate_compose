import 'dart:async';

import 'package:campus_mate/billing/model/billing_repository.dart';
import 'package:campus_mate/billing/model/billing_repository_provider.dart';
import 'package:campus_mate/billing/model/heart_store_gateway.dart';
import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:campus_mate/billing/model/heart_task_repository_provider.dart';
import 'package:campus_mate/billing/model/store_purchase.dart';
import 'package:campus_mate/billing/view/heart_bundle_card.dart';
import 'package:campus_mate/billing/view/heart_payment_notice.dart';
import 'package:campus_mate/billing/view/heart_purchase_banner.dart';
import 'package:campus_mate/billing/view/heart_purchase_bar.dart';
import 'package:campus_mate/billing/view/heart_store_screen.dart';
import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/billing/viewmodel/heart_purchase_view_model.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/entrance.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../me/model/fake_me_repository.dart';
import '../model/fake_billing_repository.dart';
import '../model/fake_heart_store_gateway.dart';
import '../model/fake_heart_task_repository.dart';
import 'pretendard.dart';

/// "무료로 모으기" 안내(pen `cVVgB` 두 줄 + 투표 지급 기준 한 줄 — 대장 지시 10-12, pen 동기화 대기).
const _notice = '초기 보상 기준 · 인증 후 지급\n100명 이후 홍보 30 / 단톡방 20 하트\n커뮤니티 투표 하루 첫 투표 1번만 10 · 한 주 최대 30 하트';

const _usage = '추가 카드는 다음 카드가 올 때까지 한 장만 열 수 있어요. 산 카드는 결정할 때까지 사라지지 않아요.';

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

/// 스토어 연결이 [release] 될 때까지 멈춰 있다 — 가격을 읽는 중(pen 에 없는 상태).
class _SlowGateway extends FakeHeartStoreGateway {
  final Completer<void> release = Completer<void>();

  @override
  Future<bool> isAvailable() async {
    await release.future;
    return super.isAvailable();
  }
}

void main() {
  setUpAll(loadPretendard);
  late FakeHeartTaskRepository tasks;
  late FakeHeartStoreGateway gateway;
  late FakeBillingRepository billing;
  late GoRouter router;

  /// null 이면 덮지 않는다 — 기기(시험 플랫폼)에 따라 진짜 provider 가 정한다.
  late bool? supported;
  late List<Uri> opened;
  late FakeMeRepository me;

  setUp(() {
    tasks = FakeHeartTaskRepository();
    gateway = FakeHeartStoreGateway();
    billing = FakeBillingRepository();
    supported = true;
    opened = [];
    me = FakeMeRepository(Success(_profile(320)));
  });

  /// 설정에서 들어온 것처럼 한 번 push 한다 — 뒤로 버튼이 보이게. 화면이 길어 스크롤 없이 다 그리도록 키를 크게 잡는다.
  Future<void> pump(
    WidgetTester tester, {
    Result<MyProfile>? profile,
    double textScale = 1,
    double height = 1900,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    router = GoRouter(
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
          meRepositoryProvider.overrideWithValue(profile == null ? me : FakeMeRepository(profile)),
          heartStoreGatewayProvider.overrideWithValue(gateway),
          billingRepositoryProvider.overrideWithValue(billing),
          if (supported case final value?) heartPurchaseSupportedProvider.overrideWithValue(value),
          openUrlProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    unawaited(router.push(AppRoutes.heartStore));
    if (settle) await tester.pumpAndSettle();
  }

  Finder cardOf(int hearts) => find.widgetWithText(HeartBundleCard, '$hearts하트');
  Finder bar() => find.byType(HeartPurchaseBar);
  Finder inBar(String text) => find.descendant(of: bar(), matching: find.text(text));
  Finder inSheet(String text) => find.descendant(of: find.byType(BottomSheet), matching: find.text(text));
  Finder badgeOf(int hearts) => find.descendant(of: cardOf(hearts), matching: find.text('첫 구매 +50'));

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

  /// 버튼 글자 · 채움 · 글자색.
  (Color?, Color?) buttonPaint(WidgetTester tester, Finder text) {
    final fill = tester.widget<Material>(find.ancestor(of: text, matching: find.byType(Material)).first).color;
    return (fill, tester.widget<Text>(text).style!.color);
  }

  Future<void> emit(WidgetTester tester, List<StorePurchaseEvent> events) async {
    gateway.emit(events);
    await tester.pump();
    await tester.pump();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(inBar('100하트 받기 · 5,700원'));
    await tester.pumpAndSettle();
  }

  group('틀(pen `IAy1j` · 15e-1 `nIiBe`)', () {
    testWidgets('앱바 `RRpV8` — 뒤로 48 (12,4), 제목 "하트" 18/700, 오른쪽 3D 도움말 24 (누름 48, x300)', (tester) async {
      await pump(tester);

      final title = tester.widget<Text>(find.descendant(of: find.byType(AppBar), matching: find.text('하트'))).style!;
      expect((title.fontSize, title.fontWeight, title.color), (18, FontWeight.w700, AppColors.ink));
      expect(tester.getRect(find.byTooltip('Back')), const Rect.fromLTWH(12, 4, 48, 48));
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

    testWidgets('섹션 제목 "구매하기" · "무료로 모으기" 20/600 ink, 구매 안내 박스', (tester) async {
      await pump(tester);

      for (final label in ['구매하기', '무료로 모으기']) {
        final style = tester.widget<Text>(find.text(label)).style!;
        expect((style.fontSize, style.fontWeight, style.color), (20, FontWeight.w600, AppColors.ink), reason: label);
      }
      expect(find.text(_usage), findsOneWidget);
    });

    testWidgets('구매 섹션 `Bbp5P` 끝에 결제 안내 `saa1s`(번들 목록 아래 12), 무료로 모으기는 그 아래 24', (tester) async {
      await pump(tester);

      final notice = find.byType(HeartPaymentNotice);
      expect(notice, findsOneWidget);
      expect(tester.getTopLeft(notice).dy - tester.getBottomLeft(cardOf(800)).dy, 12);
      expect(tester.getSize(notice).width, 328);
      expect(tester.getTopLeft(find.text('무료로 모으기')).dy - tester.getBottomLeft(notice).dy, 24);
    });

    testWidgets('상점 화면 어디에도 하네스 금지어(환급 · 선물 · 송금 · 현금 · 출금)가 없다(E-HEART-49)', (tester) async {
      await pump(tester);

      for (final word in ['환급', '선물', '송금', '현금', '출금']) {
        expect(find.textContaining(word, findRichText: true), findsNothing, reason: word);
      }
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

    testWidgets('스토어가 준 원화 가격을 쓰고 할인율을 다시 계산한다', (tester) async {
      gateway.prices = {...storePricesWon(), 'heart_200': const StorePrice(label: '₩11,400', won: 11400)};
      await pump(tester);

      expect(find.descendant(of: cardOf(200), matching: find.text('11,400원')), findsOneWidget);
      expect(find.descendant(of: cardOf(200), matching: find.text('5%')), findsOneWidget);
      expect(find.descendant(of: cardOf(200), matching: find.text('10,800원')), findsNothing);
    });

    testWidgets('원화가 아닌 스토어 가격은 글자 그대로, 원가 · 할인은 숨긴다', (tester) async {
      gateway.prices = {...storePricesWon(), 'heart_400': const StorePrice(label: r'US$14.99')};
      await pump(tester);

      expect(find.descendant(of: cardOf(400), matching: find.text(r'US$14.99')), findsOneWidget);
      expect(find.descendant(of: cardOf(400), matching: find.text('15%')), findsNothing);
      expect(find.descendant(of: cardOf(400), matching: find.text('원가')), findsNothing);
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
      expect(tester.getTopLeft(box) - tester.getRect(cardOf(100)).topLeft, const Offset(16, -9));
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

    testWidgets('낭독은 카드마다 한 번 — 수량 · 가격 · 할인 · 추천 · 첫 구매 보너스, 고른 카드는 selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel('100하트, 5,700원, 5퍼센트 할인, 추천, 첫 구매 보너스 50하트'), findsOneWidget);
      expect(find.bySemanticsLabel('800하트, 38,400원, 20퍼센트 할인, 최대 할인, 첫 구매 보너스 50하트'), findsOneWidget);
      expect(find.bySemanticsLabel('50하트, 3,000원'), findsOneWidget);
      handle.dispose();
    });
  });

  group('첫 구매 배지(pen `mflMT` BonusBadge, 슬롯 `lpyBA`)', () {
    testWidgets('첫 구매 전(15e-1) — 100 · 200 · 400 · 800 카드에만 "첫 구매 +50", 50 카드엔 없다', (tester) async {
      await pump(tester);

      for (final hearts in [100, 200, 400, 800]) {
        expect(badgeOf(hearts), findsOneWidget, reason: '$hearts');
      }
      expect(badgeOf(50), findsNothing);
    });

    testWidgets('모양 — 71×18(글자 폭 + 좌우 8), 카드 오른쪽 16 · 위 −9, 흰 채움 · 1px primary 테두리 · pill · 11/700 primaryText', (
      tester,
    ) async {
      await pump(tester);

      final label = badgeOf(100);
      final badge = find.ancestor(of: label, matching: find.byType(Container)).first;
      final card = tester.getRect(cardOf(100));
      final rect = tester.getRect(badge);
      expect(rect.height, 18);
      expect(rect.width, closeTo(tester.getSize(label).width + 16, 0.5));
      expect(rect.width, closeTo(71, 2));
      expect((card.right - rect.right, rect.top - card.top), (16, -9));
      final container = tester.widget<Container>(badge);
      final fill = container.decoration! as BoxDecoration;
      final border = container.foregroundDecoration! as BoxDecoration;
      expect((fill.color, fill.borderRadius), (AppColors.canvas, BorderRadius.circular(9999)));
      expect(((border.border! as Border).top.color, (border.border! as Border).top.width), (AppColors.primary, 1.0));
      final style = tester.widget<Text>(label).style!;
      expect((style.fontSize, style.fontWeight, style.color), (11, FontWeight.w700, AppColors.primaryText));
    });

    testWidgets('100하트 카드는 "추천" 태그와 배지가 겹치지 않는다', (tester) async {
      await pump(tester);

      final tag = tester.getRect(
        find.ancestor(of: find.descendant(of: cardOf(100), matching: find.text('추천')), matching: find.byType(Container)).first,
      );
      final badge = tester.getRect(find.ancestor(of: badgeOf(100), matching: find.byType(Container)).first);
      expect(tag.overlaps(badge), isFalse);
    });

    testWidgets('첫 구매 뒤(15e-2) — 서버가 자격 null 이면 배지가 하나도 없다', (tester) async {
      billing.status = Success(BillingStatus(accountToken: fakeAccountToken));
      await pump(tester);

      expect(find.text('첫 구매 +50'), findsNothing);
    });

    testWidgets('자격을 아직 못 읽었으면(스토어 연결 중) 배지를 보이지 않는다', (tester) async {
      gateway = _SlowGateway();
      await pump(tester, settle: false);
      await tester.pump();

      expect(find.text('첫 구매 +50'), findsNothing);
      (gateway as _SlowGateway).release.complete();
      await tester.pumpAndSettle();
      expect(find.text('첫 구매 +50'), findsNWidgets(4));
    });

    testWidgets('성공해서 서버 자격이 사라지면 배지도 사라진다', (tester) async {
      await pump(tester);
      billing.status = Success(BillingStatus(accountToken: fakeAccountToken));

      await emit(tester, [const StorePurchased('heart_100', 'tok')]);
      await tester.pump();

      expect(find.text('첫 구매 +50'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('하단 구매바(pen `GG0ei` · 15e-1 `g7Agjb`)', () {
    testWidgets('360×88, 고른 번들 이름 · 추천 캡션 · primary 버튼 "100하트 받기 · 5,700원"(오른쪽 16 · 위 12 · 높이 52)', (tester) async {
      await pump(tester);

      expect(tester.getSize(bar()), const Size(360, 88));
      expect(tester.getTopLeft(bar()).dy, 1900 - 88);
      expect(inBar('100하트'), findsOneWidget);
      expect(inBar('추천'), findsOneWidget);
      final button = inBar('100하트 받기 · 5,700원');
      expect(buttonPaint(tester, button), (AppColors.primary, AppColors.onPrimary));
      final rect = tester.getRect(find.ancestor(of: button, matching: find.byType(InkWell)).first);
      expect((rect.height, rect.right, rect.top - tester.getTopLeft(bar()).dy), (52, 344, 12));
    });

    testWidgets('다른 번들을 고르면 이름 · 버튼 글자가 바뀌고, 추천이 아니면 캡션이 사라진다', (tester) async {
      await pump(tester);

      await tester.tap(cardOf(400));
      await tester.pump();

      expect(inBar('400하트'), findsOneWidget);
      expect(inBar('400하트 받기 · 20,400원'), findsOneWidget);
      expect(inBar('추천'), findsNothing);
    });

    testWidgets('스토어 연결 중(pen 에 없는 상태)에는 같은 글자의 회색 버튼 — 눌러도 시트가 안 열린다', (tester) async {
      gateway = _SlowGateway();
      await pump(tester, settle: false);
      await tester.pump();

      final button = inBar('100하트 받기 · 5,700원');
      expect(buttonPaint(tester, button), (AppColors.primaryDisabled, AppColors.disabled));
      await tester.tap(button);
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
      (gateway as _SlowGateway).release.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('결제 불가(15e-7 `McLcn`) — 앱바 아래 빨간 배너 + 회색 "구매할 수 없어요"', (tester) async {
      gateway.available = false;
      await pump(tester);

      final banner = find.byType(HeartPurchaseBanner);
      expect(tester.getTopLeft(banner), const Offset(0, 56));
      expect(find.text('지금은 하트를 살 수 없어요'), findsOneWidget);
      expect(find.text('구글 플레이에 로그인했는지 확인해 주세요'), findsOneWidget);
      expect(buttonPaint(tester, inBar('구매할 수 없어요')), (AppColors.primaryDisabled, AppColors.disabled));
      await tester.tap(inBar('구매할 수 없어요'));
      await tester.pump();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('배너가 뜨면 본문이 배너 높이만큼 내려간다(겹치지 않는다)', (tester) async {
      gateway.available = false;
      await pump(tester);

      final bannerBottom = tester.getBottomLeft(find.byType(HeartPurchaseBanner)).dy;
      final hero = find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/images/heart-value-scene.png',
      );
      expect(tester.getTopLeft(hero).dy, bannerBottom + 8);
    });

    testWidgets('고른 상품만 스토어 가격이 없으면 그 상품은 "구매할 수 없어요"(배너 없음)', (tester) async {
      gateway.prices = Map.of(storePricesWon())..remove('heart_800');
      await pump(tester);

      await tester.tap(cardOf(800));
      await tester.pump();

      expect(inBar('구매할 수 없어요'), findsOneWidget);
      expect(find.byType(HeartPurchaseBanner), findsNothing);
    });
  });

  group('구매 확인 시트(pen 18d `yQ6Ae` · `HoALC` · `XKi8Y`)', () {
    testWidgets('보너스 있음(18d-1) — 제목 · "100하트 + 보너스 50하트 · 5,700원" 18/600 · 안내 · "5,700원에 구매" · 취소 · 결제 안내', (tester) async {
      await pump(tester);

      await openSheet(tester);

      expect(find.text('하트를 구매할까요?'), findsOneWidget);
      final product = inSheet('100하트 + 보너스 50하트 · 5,700원');
      final style = tester.widget<Text>(product).style!;
      expect((style.fontSize, style.fontWeight, style.color), (18, FontWeight.w600, AppColors.ink));
      expect(find.text(_usage), findsNWidgets(2));
      expect(buttonPaint(tester, inSheet('5,700원에 구매')), (AppColors.primary, AppColors.onPrimary));
      expect(buttonPaint(tester, inSheet('취소')), (AppColors.primaryDisabled, AppColors.ink));
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(HeartPaymentNotice)), findsOneWidget);
      final title = tester.widget<Text>(find.text('하트를 구매할까요?')).style!;
      expect((title.fontSize, title.fontWeight), (24, FontWeight.w700));
    });

    testWidgets('보너스 없음(18d-2) — "100하트 · 5,700원", 50하트는 첫 구매 전이어도 보너스 줄이 없다', (tester) async {
      await pump(tester);
      await tester.tap(cardOf(50));
      await tester.pump();

      await tester.tap(inBar('50하트 받기 · 3,000원'));
      await tester.pumpAndSettle();

      expect(inSheet('50하트 · 3,000원'), findsOneWidget);
      expect(inSheet('3,000원에 구매'), findsOneWidget);
    });

    testWidgets('시트 세로 배치 — 안쪽 [12,16,32,16] · 칸 사이 24 · 버튼 둘 328×52 · 맨 아래 결제 안내(pen 높이 554)', (tester) async {
      await pump(tester);
      await openSheet(tester);

      final buy = tester.getRect(find.ancestor(of: inSheet('5,700원에 구매'), matching: find.byType(InkWell)).first);
      final cancel = tester.getRect(find.ancestor(of: inSheet('취소'), matching: find.byType(InkWell)).first);
      final notice = tester.getRect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(HeartPaymentNotice)));
      expect((buy.size, cancel.size), (const Size(328, 52), const Size(328, 52)));
      expect((cancel.top - buy.bottom, notice.top - cancel.bottom), (24, 24));
      expect(tester.getBottomLeft(find.byType(BottomSheet)).dy - notice.bottom, 32);
      expect(buy.left, 16);
    });

    testWidgets('"5,700원에 구매" → 결제 창(계정 표시와 함께), 결제 창 대기(18d-3) — 회색 도는 표시 "결제 진행 중이에요" · 취소 꺼짐', (tester) async {
      await pump(tester);
      await openSheet(tester);

      await tester.tap(inSheet('5,700원에 구매'));
      await tester.pump();

      expect(gateway.bought, [('heart_100', fakeAccountToken)]);
      final busy = inSheet('결제 진행 중이에요');
      expect(buttonPaint(tester, busy), (AppColors.primaryDisabled, AppColors.disabled));
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(buttonPaint(tester, inSheet('취소')), (AppColors.primaryDisabled, AppColors.disabled));
      await tester.tap(inSheet('취소'));
      await tester.pump();
      expect(find.byType(BottomSheet), findsOneWidget, reason: '결제 창이 떠 있는 동안 시트는 닫히지 않는다');
      await emit(tester, [const StorePurchaseCanceled('')]);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });

    testWidgets('결제 창을 못 열면 시트가 닫히고 결제 실패 배너(15e-8 `mvOHm`) + 지난 결제 복구', (tester) async {
      gateway.opens = false;
      await pump(tester);
      await openSheet(tester);
      final recovered = gateway.recoverCount;

      await tester.tap(inSheet('5,700원에 구매'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('결제가 되지 않았어요'), findsOneWidget);
      expect(gateway.recoverCount, recovered + 1);
    });

    testWidgets('결제 창에서 취소 → 시트가 닫히고 "결제를 취소했어요" 토스트(info), 2초 뒤 사라진다', (tester) async {
      await pump(tester);
      await openSheet(tester);
      await tester.tap(inSheet('5,700원에 구매'));
      await tester.pump();

      await emit(tester, [const StorePurchaseCanceled('')]);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.widgetWithText(AppToast, '결제를 취소했어요'), findsOneWidget);
      expect(tester.widget<Icon>(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon))).icon, AppIcons.info);
      // 나타날 때 나 탭 · 홈 토스트와 같이 아래 8 에서 press 동안 올라온다(D4).
      final entrance = tester.widget<Entrance>(find.ancestor(of: find.byType(AppToast), matching: find.byType(Entrance)));
      expect((entrance.rise, entrance.duration, entrance.curve), (8, AppMotion.press, AppMotion.pressCurve));
      expect(buttonPaint(tester, inBar('100하트 받기 · 5,700원')), (AppColors.primary, AppColors.onPrimary));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(AppToast), findsNothing);
    });

    testWidgets('결제됨 → 시트가 닫히고 확인 중(15e-3) — 토스트 "하트를 넣고 있어요" + 바 회색 "결제 확인 중이에요"', (tester) async {
      billing.holdVerify = Completer<void>();
      await pump(tester);
      await openSheet(tester);
      await tester.tap(inSheet('5,700원에 구매'));
      await tester.pump();

      await emit(tester, [const StorePurchased('heart_100', 'tok')]);
      // 도는 표시가 계속 움직여 pumpAndSettle 은 끝나지 않는다 — 시트 닫힘 애니메이션만큼 넘긴다.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.widgetWithText(AppToast, '하트를 넣고 있어요'), findsOneWidget);
      final busy = inBar('결제 확인 중이에요');
      expect(buttonPaint(tester, busy), (AppColors.primaryDisabled, AppColors.disabled));
      expect(find.descendant(of: bar(), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      // pen `eZlLw`: 토스트 아래 끝은 바 위 12.
      expect(tester.getTopLeft(bar()).dy - tester.getBottomLeft(find.byType(AppToast)).dy, 12);
      await tester.pump(const Duration(seconds: 3));
      expect(find.widgetWithText(AppToast, '하트를 넣고 있어요'), findsOneWidget, reason: '확인이 끝날 때까지 남는다');
      billing.holdVerify!.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('성공(15e-4) — "150하트가 들어왔어요(보너스 50 포함)" circle-check 토스트, 바는 다시 primary, 잔액을 다시 읽는다', (tester) async {
      await pump(tester);
      await openSheet(tester);
      await tester.tap(inSheet('5,700원에 구매'));
      await tester.pump();
      me.profile = Success(_profile(470));

      await emit(tester, [const StorePurchased('heart_100', 'tok')]);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.widgetWithText(AppToast, '150하트가 들어왔어요(보너스 50 포함)'), findsOneWidget);
      expect(
        tester.widget<Icon>(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon))).icon,
        AppIcons.circleCheck,
      );
      expect(buttonPaint(tester, inBar('100하트 받기 · 5,700원')), (AppColors.primary, AppColors.onPrimary));
      expect(find.text('470개'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('성공(15e-5) 보너스 없음 — "100하트가 들어왔어요"', (tester) async {
      billing.outcome = const Success(PurchaseGranted(hearts: 100, bonusHearts: 0, isNew: true));
      await pump(tester);
      await openSheet(tester);
      await tester.tap(inSheet('5,700원에 구매'));
      await tester.pump();

      await emit(tester, [const StorePurchased('heart_100', 'tok')]);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.widgetWithText(AppToast, '100하트가 들어왔어요'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('제목줄 도움말은 시트를 닫고 하트·결제 FAQ 로 간다', (tester) async {
      await pump(tester);
      await openSheet(tester);

      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.byTooltip('도움말')));
      await tester.pumpAndSettle();

      expect(find.text('21 자주 묻는 질문'), findsOneWidget);
    });

    testWidgets('"취소" 는 닫기만 한다 — 결제 창 없음 · 토스트 없음', (tester) async {
      await pump(tester);
      await openSheet(tester);

      await tester.tap(inSheet('취소'));
      await tester.pumpAndSettle();

      expect(find.text('하트를 구매할까요?'), findsNothing);
      expect(find.byType(AppToast), findsNothing);
      expect(gateway.bought, isEmpty);
    });

    testWidgets('시트의 약관 링크도 같은 주소를 연다', (tester) async {
      await pump(tester);
      await openSheet(tester);

      await tester.tap(inSheet('유료 서비스 약관 ›'));
      await tester.pump();

      expect(opened, hasLength(1));
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 배율 $scale 에서도 시트가 넘치지 않고 모든 버튼에 닿는다(보너스 줄 포함)', (tester) async {
        await pump(tester, textScale: scale, height: 700);
        await tester.tap(find.descendant(of: bar(), matching: find.byType(InkWell)).first);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(inSheet('유료 서비스 약관 ›'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(inSheet('취소'), findsOneWidget);
      });
    }

    testWidgets('앱바의 도움말도 FAQ 로 간다', (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip('도움말').first);
      await tester.pumpAndSettle();

      expect(find.text('21 자주 묻는 질문'), findsOneWidget);
    });
  });

  group('안내 · 오류(15e-6 `HtSoW` · 15e-8 `JGoPI`)', () {
    Future<void> buyThen(WidgetTester tester, List<StorePurchaseEvent> events) async {
      await openSheet(tester);
      await tester.tap(inSheet('5,700원에 구매'));
      await tester.pump();
      await emit(tester, events);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }

    testWidgets('지급 지연(서버 503) — 앱바 바로 아래 배너 + 바 회색 "지급 확인 중이에요"(도는 표시 없음)', (tester) async {
      billing.outcome = const FailureResult(ServerUnavailableFailure());
      await pump(tester);

      await buyThen(tester, [const StorePurchased('heart_100', 'tok')]);

      expect(tester.getTopLeft(find.byType(HeartPurchaseBanner)), const Offset(0, 56));
      expect(find.text('하트 지급이 늦어지고 있어요'), findsOneWidget);
      expect(find.text('앱을 다시 열면 이어서 들어와요'), findsOneWidget);
      expect(buttonPaint(tester, inBar('지급 확인 중이에요')), (AppColors.primaryDisabled, AppColors.disabled));
      expect(find.descendant(of: bar(), matching: find.byType(CircularProgressIndicator)), findsNothing);
      expect(find.byType(AppToast), findsNothing);
    });

    testWidgets('배너는 상점을 나갔다 들어오면 사라진다(닫기 버튼 없음)', (tester) async {
      await pump(tester);
      await buyThen(tester, [const StorePurchaseFailed('')]);
      expect(find.text('결제가 되지 않았어요'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      unawaited(router.push(AppRoutes.heartStore));
      await tester.pumpAndSettle();

      expect(find.byType(HeartPurchaseBanner), findsNothing);
      expect(find.byType(IconButton), findsNWidgets(2), reason: '앱바의 뒤로 · 도움말뿐');
    });

    testWidgets('배너는 다시 구매를 시도하면 사라진다', (tester) async {
      await pump(tester);
      await buyThen(tester, [const StorePurchasePending('heart_100')]);
      expect(find.text('결제 확인을 기다리고 있어요'), findsOneWidget);

      await openSheet(tester);
      await tester.tap(inSheet('5,700원에 구매'));
      await tester.pump();

      expect(find.byType(HeartPurchaseBanner), findsNothing);
      await emit(tester, [const StorePurchaseCanceled('')]);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    for (final (outcome, title) in [
      (const FailureResult<PurchaseOutcome>(ServerRejectedFailure('x', code: 'purchase_other_account')), '다른 계정으로 결제한 하트예요'),
      (const FailureResult<PurchaseOutcome>(ServerRejectedFailure('x', code: 'purchase_invalid')), '결제를 확인하지 못했어요'),
      (const Success<PurchaseOutcome>(PurchasePendingAtStore()), '결제 확인을 기다리고 있어요'),
    ]) {
      testWidgets('서버 답 → 배너 "$title", 바는 다시 살 수 있다', (tester) async {
        billing.outcome = outcome;
        await pump(tester);

        await buyThen(tester, [const StorePurchased('heart_100', 'tok')]);

        expect(find.descendant(of: find.byType(HeartPurchaseBanner), matching: find.text(title)), findsOneWidget);
        expect(buttonPaint(tester, inBar('100하트 받기 · 5,700원')), (AppColors.primary, AppColors.onPrimary));
      });
    }

    testWidgets('이미 처리(409 purchase_token_used) → "이미 처리된 결제예요" 토스트(circle-check)', (tester) async {
      billing.outcome = const FailureResult(ServerRejectedFailure('x', code: 'purchase_token_used'));
      await pump(tester);

      await buyThen(tester, [const StorePurchased('heart_100', 'tok')]);

      expect(find.widgetWithText(AppToast, '이미 처리된 결제예요'), findsOneWidget);
      expect(find.byType(HeartPurchaseBanner), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('글자 배율 2.0 — 확인 실패 배너(메일 주소)가 넘치지 않는다', (tester) async {
      billing.outcome = const FailureResult(ServerRejectedFailure('x', code: 'purchase_invalid'));
      await pump(tester, textScale: 2, height: 900);

      await tester.tap(find.descendant(of: bar(), matching: find.byType(InkWell)).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.descendant(of: find.byType(BottomSheet), matching: find.byType(InkWell)).first);
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.byType(InkWell)).at(1));
      await tester.pump();
      await emit(tester, [const StorePurchased('heart_100', 'tok')]);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.byType(HeartPurchaseBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('iOS(App Store)', () {
    final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

    testWidgets('구매 섹션 · 하단 바가 보이고 결제 안내는 App Store 판 — 구글 플레이를 말하지 않는다', (tester) async {
      supported = null;
      await pump(tester);

      expect(find.text('구매하기'), findsOneWidget);
      expect(find.byType(HeartBundleCard), findsNWidgets(5));
      expect(inBar('100하트 받기 · 5,700원'), findsOneWidget);
      expect(find.text('결제는 App Store로 처리돼요'), findsOneWidget);
      expect(find.textContaining('구글'), findsNothing);
    }, variant: ios);

    testWidgets('구매 → 결제 창에는 애플 계정 표시(UUID)', (tester) async {
      supported = null;
      await pump(tester);
      await openSheet(tester);

      await tester.tap(inSheet('5,700원에 구매'));
      await tester.pump();

      expect(gateway.bought, [('heart_100', fakeAppleAccountToken)]);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('결제는 App Store로 처리돼요')), findsOneWidget);
      await emit(tester, [const StorePurchaseCanceled('')]);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }, variant: ios);

    testWidgets('스토어 가격을 못 읽으면(상품 미등록 · 샌드박스 불가) 구글처럼 결제 불가 배너 — 설명은 App Store', (tester) async {
      supported = null;
      gateway.prices = {};
      await pump(tester);

      expect(find.text('지금은 하트를 살 수 없어요'), findsOneWidget);
      expect(find.text('이 기기에서 App Store 결제를 쓸 수 없거나 상품을 불러오지 못했어요'), findsOneWidget);
      expect(inBar('구매할 수 없어요'), findsOneWidget);
    }, variant: ios);

    testWidgets('서버 상태(/billing/status)를 못 읽어도(연결 실패) 결제 불가 설명은 App Store 판 — 구글 플레이를 말하지 않는다', (tester) async {
      supported = null;
      billing.status = const FailureResult(NetworkFailure());
      await pump(tester);

      expect(find.textContaining('구글'), findsNothing);
      expect(find.text('지금은 하트를 살 수 없어요'), findsOneWidget);
      expect(find.text('이 기기에서 App Store 결제를 쓸 수 없거나 상품을 불러오지 못했어요'), findsOneWidget);
    }, variant: ios);

    testWidgets('환불된 거래(422 purchase_revoked) → "환불된 결제예요" 토스트(info) — 성공 표시(circle-check)가 아니다', (tester) async {
      supported = null;
      billing.outcome = const FailureResult(ServerRejectedFailure('x', code: 'purchase_revoked'));
      await pump(tester);
      await openSheet(tester);

      await tester.tap(inSheet('5,700원에 구매'));
      await tester.pump();
      await emit(tester, [const StorePurchased('heart_100', '2000000123456789')]);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.widgetWithText(AppToast, '환불된 결제예요'), findsOneWidget);
      expect(tester.widget<Icon>(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon))).icon, AppIcons.info);
      expect(find.byType(HeartPurchaseBanner), findsNothing);
      expect(gateway.finished, ['2000000123456789']);
      await tester.pump(const Duration(seconds: 2));
    }, variant: ios);
  });

  group('웹 · 데스크톱(15e-9 `GKEM9`)', () {
    testWidgets('구매 섹션 · 하단 바 · 배너가 없고 무료로 모으기가 보유 하트 바로 아래(y332)', (tester) async {
      supported = false;
      gateway.available = false;
      await pump(tester);

      expect(find.text('구매하기'), findsNothing);
      expect(find.byType(HeartBundleCard), findsNothing);
      expect(bar(), findsNothing);
      expect(find.byType(HeartPurchaseBanner), findsNothing);
      expect(find.byType(HeartPaymentNotice), findsNothing);
      // pen: 보유 하트 블록 아래 24 에 무료로 모으기(y332). 블록 자체 높이(앱 91 · pen 렌더 96)는 기존 차이 — 보고에 적는다.
      final balance = find.ancestor(of: find.text('보유 하트'), matching: find.byType(Padding)).first;
      expect(tester.getTopLeft(find.text('무료로 모으기')).dy - tester.getBottomLeft(balance).dy, 24);
      expect(find.text('320개'), findsOneWidget);
      expect(gateway.availableCount, 0, reason: '결제 코드가 돌지 않는다');
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
      expect(find.text(_notice), findsOneWidget);
    });

    testWidgets('투표 줄 — "하루 1번" 배지가 길어져도(Pretendard) 줄은 328×64, 제목 · 배지 모두 한 줄', (tester) async {
      await pump(tester);

      final vote = find.byType(HeartTaskRow).at(2);
      expect(tester.getSize(vote), const Size(328, 64));
      expect(tester.getSize(find.descendant(of: vote, matching: find.text('커뮤니티 투표'))).height, 20);
      final badge = find.ancestor(of: find.text('하루 1번'), matching: find.byType(Container)).first;
      expect(tester.getSize(badge).height, 20);
    });

    testWidgets('안내 `cVVgB` 셋째 줄은 투표 지급 기준 — 12/400 muted 줄높이 1.4, 한 줄씩 세 줄(16.8 × 3)', (tester) async {
      await pump(tester);

      final notice = find.text(_notice);
      final style = tester.widget<Text>(notice).style!;
      expect((style.fontSize, style.fontWeight, style.height, style.color), (12, FontWeight.w400, 1.4, AppColors.muted));
      expect(tester.getSize(notice).height / (12 * 1.4), closeTo(3, 0.1), reason: '셋째 줄이 360 폭에서 접히지 않는다');
    });

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('글자 배율 $scale — 제목 → 4 → 안내 → 12 → 첫 줄, 안내는 잘리지 않고 늘어나기만 한다', (tester) async {
        await pump(tester, textScale: scale, height: 3200);

        final title = tester.getRect(find.text('무료로 모으기'));
        final notice = tester.getRect(find.text(_notice));
        final firstRow = tester.getRect(find.byType(HeartTaskRow).first);
        expect(notice.top - title.bottom, closeTo(4, 0.5));
        expect(firstRow.top - notice.bottom, closeTo(12, 0.5));
        expect(notice.height, greaterThanOrEqualTo(3 * 12 * 1.4 * scale - 0.5));
        expect(tester.widget<Text>(find.text(_notice)).maxLines, isNull);
        expect(tester.takeException(), isNull);
      });
    }

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

      expect(find.descendant(of: find.byType(ListView), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
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

      await tester.ensureVisible(find.text('다시 시도'));
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(tasks.fetchCount, asked + 1);
      expect(find.byType(HeartTaskRow), findsNWidgets(3));
    });
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('글자 배율 $scale 에서도 넘침 오류가 없고 카드 높이는 88 이상이다(스크롤 끝까지 · 바 포함)', (tester) async {
      await pump(tester, textScale: scale, height: 780);

      for (final hearts in [50, 100, 200, 400, 800]) {
        await tester.ensureVisible(cardOf(hearts));
        await tester.pump();
        expect(tester.getSize(cardOf(hearts)).height, greaterThanOrEqualTo(88), reason: '$hearts');
        expect(tester.getSize(cardOf(hearts)).width, 328, reason: '$hearts');
      }
      await tester.tap(cardOf(800));
      await tester.pump();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(inBar('800하트 받기 · 38,400원'), findsOneWidget, reason: '긴 버튼 글자는 줄여 넣지 자르지 않는다');
    });
  }
}
