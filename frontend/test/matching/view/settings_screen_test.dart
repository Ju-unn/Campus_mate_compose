import 'package:campus_mate/account/view/withdraw_sheets.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/view/settings_screen.dart';
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

import '../../safety/model/fake_contact_blocks.dart';
import '../../safety/model/fake_safety_repository.dart';
import '../model/fake_card_repository.dart';

void main() {
  var signOutCalls = 0;

  Future<FakeCardRepository> pump(WidgetTester tester, {FakeDeviceContactSource? contacts}) async {
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
    expect(tester.getRect(tile('로그아웃')).top, tester.getRect(tile('연락처 차단')).bottom);
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

    await tester.tap(find.text('탈퇴하기'));
    await tester.pumpAndSettle();

    expect(find.byType(WithdrawFirstSheet), findsOneWidget);
  });
}
