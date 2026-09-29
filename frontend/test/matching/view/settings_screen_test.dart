import 'dart:async';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/view/account_screen.dart';
import 'package:campus_mate/account/view/withdraw_sheets.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/faq/model/faq_cache.dart';
import 'package:campus_mate/faq/model/faq_item.dart';
import 'package:campus_mate/faq/model/faq_repository.dart';
import 'package:campus_mate/faq/view/faq_screen.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/settings_screen.dart';
import 'package:campus_mate/referral/model/invite_share.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:campus_mate/referral/view/invite_friends_sheet.dart';
import 'package:campus_mate/safety/model/contact_block_repository.dart';
import 'package:campus_mate/safety/model/contact_name_store.dart';
import 'package:campus_mate/safety/model/device_contacts.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/block_list_screen.dart';
import 'package:campus_mate/safety/view/contact_block_list_screen.dart';
import 'package:campus_mate/safety/view/contact_picker_screen.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../account/model/fake_account_repository.dart';
import '../../faq/model/fake_faq.dart';
import '../../referral/model/fake_referral_repository.dart';
import '../../safety/model/fake_contact_blocks.dart';
import '../../safety/model/fake_safety_repository.dart';
import '../model/fake_card_repository.dart';

void main() {
  var signOutCalls = 0;

  Future<FakeCardRepository> pump(
    WidgetTester tester, {
    FakeDeviceContactSource? contacts,
    List<FaqItem> faq = faqFixture,
    Future<void>? faqGate,
  }) async {
    signOutCalls = 0;
    final repository = FakeCardRepository();
    final container = ProviderContainer(
      overrides: [
        cardRepositoryProvider.overrideWithValue(repository),
        safetyRepositoryProvider.overrideWithValue(FakeSafetyRepository()),
        signOutProvider.overrideWithValue(() async => signOutCalls++),
        deviceContactSourceProvider.overrideWithValue(contacts ?? FakeDeviceContactSource()),
        contactBlockRepositoryProvider.overrideWithValue(FakeContactBlockRepository()),
        contactNameStoreProvider.overrideWithValue(FakeContactNameStore()),
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        referralRepositoryProvider.overrideWithValue(FakeReferralRepository()),
        shareTextProvider.overrideWithValue((_) async {}),
        faqRepositoryProvider.overrideWithValue(FakeFaqRepository(Success(faq), gate: faqGate)),
        faqCacheProvider.overrideWithValue(FakeFaqCache()),
      ],
    );
    addTearDown(container.dispose);
    // 줄을 누르면 push 로 다음 화면이 열린다 — 라우터 안에서 띄운다.
    final router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: [
        GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsScreen()),
        GoRoute(path: AppRoutes.blockList, builder: (context, state) => const BlockListScreen()),
        GoRoute(path: AppRoutes.contactBlocks, builder: (context, state) => const ContactBlockListScreen()),
        GoRoute(path: AppRoutes.contactPicker, builder: (context, state) => const ContactPickerScreen()),
        GoRoute(path: AppRoutes.account, builder: (context, state) => const AccountScreen()),
        GoRoute(path: AppRoutes.heartTasks, builder: (context, state) => const Text('18a')),
        GoRoute(path: AppRoutes.faq, builder: (context, state) => const FaqScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    return repository;
  }

  Finder tile(String title) => find.ancestor(of: find.text(title), matching: find.byType(ListTile));

  // 줄 제목과 시트 확인 버튼 글자가 둘 다 "로그아웃" 이다 — 시트 안으로 좁혀 찾는다.
  Finder inSheet(String text) =>
      find.descendant(of: find.byType(SafetyConfirmSheet), matching: find.text(text));

  Future<void> openLogoutSheet(WidgetTester tester) async {
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
  }

  testWidgets('매칭 활성화를 끄면 일시중지 참으로 보낸다', (tester) async {
    final repository = await pump(tester);

    await tester.tap(find.text('매칭 활성화'));
    await tester.pump();

    expect(repository.pausedValue, isTrue);
  });

  testWidgets('"계정" 줄은 매칭 활성화와 알림 사이, user-round 아이콘과 셰브런이다(pen lMDpY eCrlw)', (tester) async {
    await pump(tester);

    expect(tile('계정'), findsOneWidget);
    expect(tester.getRect(tile('계정')).bottom, tester.getRect(tile('알림')).top);
    expect(tester.getRect(tile('계정')).top, greaterThan(tester.getRect(find.text('매칭 활성화')).bottom));
    expect(find.descendant(of: tile('계정'), matching: find.byIcon(AppIcons.userRound)), findsOneWidget);
    expect(find.descendant(of: tile('계정'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"친구 초대" 줄은 계정 바로 위, user-plus 아이콘과 셰브런, 설명 줄이 있다(pen lMDpY b1fvA)', (tester) async {
    await pump(tester);

    expect(tile('친구 초대'), findsOneWidget);
    expect(find.descendant(of: tile('친구 초대'), matching: find.text('내 추천 코드를 친구에게 보내요')), findsOneWidget);
    expect(tester.getRect(tile('친구 초대')).bottom, tester.getRect(tile('계정')).top);
    expect(find.descendant(of: tile('친구 초대'), matching: find.byIcon(AppIcons.userPlus)), findsOneWidget);
    expect(find.descendant(of: tile('친구 초대'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"친구 초대" 를 누르면 16i 시트가 열린다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('친구 초대'));
    await tester.pumpAndSettle();
    expect(find.byType(InviteFriendsSheet), findsOneWidget);
    expect(find.text('K7QMX2'), findsOneWidget);
  });

  testWidgets('"계정" 을 누르면 16e 가 열린다', (tester) async {
    await pump(tester);
    await tester.tap(find.text('계정'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
  });

  testWidgets('"차단 목록" 줄은 알림 바로 아래, user-x 아이콘이다(pen lMDpY 8번 o0km6)', (tester) async {
    await pump(tester);

    expect(tile('차단 목록'), findsOneWidget);
    expect(tester.getRect(tile('차단 목록')).top, tester.getRect(tile('알림')).bottom);
    expect(find.descendant(of: tile('차단 목록'), matching: find.byIcon(AppIcons.userX)), findsOneWidget);
    expect(find.descendant(of: tile('차단 목록'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"차단 목록" 을 누르면 16f 차단 목록이 열린다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('차단 목록'));
    await tester.pumpAndSettle();

    expect(find.byType(BlockListScreen), findsOneWidget);
  });

  testWidgets('"연락처 차단" 줄은 차단 목록 바로 아래, contact-round 아이콘이다(pen lMDpY eGPnB)', (tester) async {
    await pump(tester);

    expect(tile('연락처 차단'), findsOneWidget);
    expect(tester.getRect(tile('연락처 차단')).top, tester.getRect(tile('차단 목록')).bottom);
    expect(find.descendant(of: tile('연락처 차단'), matching: find.byIcon(AppIcons.contactRound)), findsOneWidget);
    expect(find.descendant(of: tile('연락처 차단'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('권한이 이미 있으면 "연락처 차단" 은 16b 로 바로 간다', (tester) async {
    await pump(tester, contacts: FakeDeviceContactSource(granted: true));

    await tester.tap(find.text('연락처 차단'));
    await tester.pumpAndSettle();

    expect(find.byType(ContactBlockListScreen), findsOneWidget);
  });

  testWidgets('권한이 없으면 "연락처 차단" 은 8a 안내 시트를 띄운다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('연락처 차단'));
    await tester.pumpAndSettle();

    expect(find.text('연락처 접근을 허용해 주세요'), findsOneWidget);
    expect(find.byType(ContactBlockListScreen), findsNothing);
  });

  // 앱 16 은 아직 섹션 카드가 없어 pen 순서(연락처 차단 → [지원] FAQ → … → 로그아웃)만 따른다 — 카드 · 아이콘 색은 백로그 70.
  testWidgets('"자주 묻는 질문" 줄은 연락처 차단 바로 아래, circle-question-mark 아이콘과 셰브런이다(pen lMDpY l1K4Xa)',
      (tester) async {
    await pump(tester);

    expect(tester.getRect(tile('자주 묻는 질문')).top, tester.getRect(tile('연락처 차단')).bottom);
    expect(
      find.descendant(of: tile('자주 묻는 질문'), matching: find.byIcon(AppIcons.circleQuestionMark)),
      findsOneWidget,
    );
    expect(find.descendant(of: tile('자주 묻는 질문'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"자주 묻는 질문" 을 누르면 21 이 열린다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('자주 묻는 질문'));
    await tester.pumpAndSettle();

    expect(find.byType(FaqScreen), findsOneWidget);
  });

  testWidgets('받는 중에도 줄이 보인다 — 늦게 튀어나와 아래 줄을 밀지 않게(대장 Q3)', (tester) async {
    final gate = Completer<void>();
    await pump(tester, faqGate: gate.future);
    await tester.pump();

    expect(find.text('자주 묻는 질문'), findsOneWidget);
    gate.complete();
  });

  testWidgets('받지도 못하고 캐시도 없어 빈 목록이면 줄이 없다(DESIGN §8.13)', (tester) async {
    await pump(tester, faq: const []);
    await tester.pumpAndSettle();

    expect(find.text('자주 묻는 질문'), findsNothing);
    expect(tester.getRect(tile('로그아웃')).top, tester.getRect(tile('연락처 차단')).bottom);
  });

  testWidgets('모든 줄의 눌림 효과는 그 줄 안에서 그려진다', (tester) async {
    // 잉크는 가장 가까운 Material 에 그린다 — 그게 Scaffold 면 목록을 밀어도 테두리가 제자리에 떠 있다(COMMON §4-2).
    // 스위치 줄도 안에 ListTile 을 두므로 ListTile 만 훑으면 나중에 더해지는 줄까지 같이 본다.
    await pump(tester);

    final tiles = find.byType(ListTile);
    expect(tiles, findsWidgets);
    for (var i = 0; i < tiles.evaluate().length; i++) {
      final material = find.ancestor(of: tiles.at(i), matching: find.byType(Material)).first;
      expect(tester.getSize(material), tester.getSize(tiles.at(i)));
    }
  });

  testWidgets('"로그아웃" 줄은 차단 목록 아래, log-out 아이콘과 셰브런이다(pen lMDpY ErFPL)', (tester) async {
    await pump(tester);

    expect(tile('로그아웃'), findsOneWidget);
    expect(tester.getRect(tile('로그아웃')).top, tester.getRect(tile('자주 묻는 질문')).bottom);
    expect(find.descendant(of: tile('로그아웃'), matching: find.byIcon(AppIcons.logOut)), findsOneWidget);
    expect(find.descendant(of: tile('로그아웃'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"로그아웃" 을 누르면 16g 문구가 보인다(pen ZkOEb)', (tester) async {
    await pump(tester);
    await openLogoutSheet(tester);

    expect(inSheet('로그아웃할까요?'), findsOneWidget);
    expect(inSheet('다시 로그인하려면 학교 이메일로 인증 코드를 한 번 더 받아야 해요.'), findsOneWidget);
    expect(inSheet('로그아웃'), findsOneWidget);
    expect(inSheet('취소'), findsOneWidget);
  });

  testWidgets('확인하면 시트가 닫히고 로그아웃을 한 번 부른다 — 빠르게 두 번 눌러도 한 번', (tester) async {
    // 닫히는 시트는 누름을 아래 화면으로 흘려보낸다 — 두 번째 탭 자리 밑에 설정 줄이 오지 않게 화면을 길게 둔다.
    tester.view.physicalSize = const Size(800, 1400) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await pump(tester);
    await openLogoutSheet(tester);

    await tester.tap(inSheet('로그아웃'));
    await tester.pump();
    // 닫히는 중인 시트를 한 번 더 누른다 — 두 번째 pop 이 설정 화면까지 닫으면 안 된다.
    await tester.tap(inSheet('로그아웃'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(signOutCalls, 1);
    expect(find.byType(SafetyConfirmSheet), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('취소 · 바깥 누르기는 로그아웃을 부르지 않는다', (tester) async {
    await pump(tester);

    await openLogoutSheet(tester);
    await tester.tap(inSheet('취소'));
    await tester.pumpAndSettle();
    await openLogoutSheet(tester);
    await tester.tapAt(const Offset(10, 10)); // 딤
    await tester.pumpAndSettle();

    expect(signOutCalls, 0);
    expect(find.byType(SafetyConfirmSheet), findsNothing);
  });

  // 대장 결정 2(2026-09-28): 탈퇴하기는 목록 줄이 아니라 목록 아래 위험 영역 단독 버튼이다.
  testWidgets('"탈퇴하기"는 목록 밖, 로그아웃 아래 위험 영역 버튼이다(pen VmUvb · rlWDn)', (tester) async {
    await pump(tester);

    final button = find.ancestor(of: find.text('탈퇴하기'), matching: find.byType(AppButton));
    // button-danger = #E5E5E5 채움 · #C13515 글자 · 56 · 모서리 16 · 18/700(DESIGN §8.3).
    expect(tester.widget<AppButton>(button).variant, AppButtonVariant.danger);
    expect(find.ancestor(of: find.text('탈퇴하기'), matching: find.byType(ListTile)), findsNothing);
    // VmUvb padding [24,16,28,16].
    expect(tester.getRect(button).top, tester.getRect(tile('로그아웃')).bottom + 24);
    expect(tester.getRect(button).left, 16);
    expect(tester.getSize(button).height, 56);
    // 아래 28 — 위험 영역 틀(Padding)의 바닥이 버튼 바닥보다 28 아래다.
    final zone = find.ancestor(of: button, matching: find.byType(Padding)).first;
    expect(tester.getRect(zone).bottom - tester.getRect(button).bottom, 28);
  });

  testWidgets('"탈퇴하기"를 누르면 16c 1차 시트가 뜬다', (tester) async {
    await pump(tester);

    // "자주 묻는 질문" 줄이 더해져 800×600 테스트 화면에선 버튼이 접힘 아래에 있다 — 밀어서 보이게 한 뒤 누른다.
    await tester.ensureVisible(find.text('탈퇴하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탈퇴하기'));
    await tester.pumpAndSettle();

    expect(find.byType(WithdrawFirstSheet), findsOneWidget);
  });

  testWidgets('"무료로 하트 모으기" 줄은 매칭 활성화 바로 아래 · 친구 초대 바로 위, gift 아이콘과 셰브런이다(pen lMDpY oNgRd)', (tester) async {
    await pump(tester);

    expect(tile('무료로 하트 모으기'), findsOneWidget);
    expect(tester.getRect(tile('무료로 하트 모으기')).top, tester.getRect(tile('매칭 활성화')).bottom);
    expect(tester.getRect(tile('무료로 하트 모으기')).bottom, tester.getRect(tile('친구 초대')).top);
    expect(find.descendant(of: tile('무료로 하트 모으기'), matching: find.byIcon(AppIcons.gift)), findsOneWidget);
    expect(find.descendant(of: tile('무료로 하트 모으기'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"무료로 하트 모으기" 를 누르면 18a 로 간다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('무료로 하트 모으기'));
    await tester.pumpAndSettle();

    expect(find.text('18a'), findsOneWidget);
  });
}
