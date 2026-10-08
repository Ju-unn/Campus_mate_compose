import 'dart:async';

import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/view/account_screen.dart';
import 'package:campus_mate/account/view/withdraw_sheets.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/consent/model/consent_links.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/faq/model/faq_cache.dart';
import 'package:campus_mate/faq/model/faq_item.dart';
import 'package:campus_mate/faq/model/faq_repository.dart';
import 'package:campus_mate/faq/view/faq_screen.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
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
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../account/model/fake_account_repository.dart';
import '../../faq/model/fake_faq.dart';
import '../../me/model/fake_me_repository.dart';
import '../../referral/model/fake_referral_repository.dart';
import '../../safety/model/fake_contact_blocks.dart';
import '../../safety/model/fake_safety_repository.dart';
import '../model/fake_card_repository.dart';

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

/// 잔액을 늦게 주는 가짜 — [gate] 가 끝나기 전까지는 읽는 중이다.
class _SlowMeRepository extends FakeMeRepository {
  _SlowMeRepository(super.profile, this.gate);

  final Future<void> gate;

  @override
  Future<Result<MyProfile>> fetchProfile() async {
    await gate;
    return super.fetchProfile();
  }
}

void main() {
  var signOutCalls = 0;
  late List<Uri> opened;
  late Future<bool> Function(Uri) openUrl;

  Future<FakeCardRepository> pump(
    WidgetTester tester, {
    FakeDeviceContactSource? contacts,
    List<FaqItem> faq = faqFixture,
    Future<void>? faqGate,
    Result<MyProfile>? profile,
    Future<void>? profileGate,
  }) async {
    signOutCalls = 0;
    opened = [];
    openUrl = (uri) async {
      opened.add(uri);
      return true;
    };
    // 네 섹션 카드가 한 화면에 다 그려지게 길게 둔다 — 목록은 화면 밖 줄을 만들지 않는다.
    tester.view.physicalSize = const Size(800, 1400) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    final repository = FakeCardRepository();
    final container = ProviderContainer(
      overrides: [
        cardRepositoryProvider.overrideWithValue(repository),
        meRepositoryProvider.overrideWithValue(
          profileGate == null
              ? FakeMeRepository(profile ?? Success(_profile(320)))
              : _SlowMeRepository(profile ?? Success(_profile(320)), profileGate),
        ),
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
        openUrlProvider.overrideWithValue((uri) => openUrl(uri)),
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
        GoRoute(path: AppRoutes.heartStore, builder: (context, state) => const Text('18 스토어')),
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

  Icon3d icon3d(WidgetTester tester, String title) =>
      tester.widget<Icon3d>(find.descendant(of: tile(title), matching: find.byType(Icon3d)));

  /// 줄 아래 선(pen 행 stroke bottom #EBEBEB 1). 섹션 마지막 줄은 지운다.
  BorderSide divider(WidgetTester tester, String title) {
    final box = tester.widget<DecoratedBox>(find.ancestor(of: tile(title), matching: find.byType(DecoratedBox)).first);
    return ((box.decoration as BoxDecoration).border as Border?)?.bottom ?? BorderSide.none;
  }

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

  testWidgets('"계정" 줄은 계정·정보 카드 첫 줄, 3D 프로필 24 와 셰브런이다(pen lMDpY eCrlw · hoe2L)', (tester) async {
    await pump(tester);

    expect(tile('계정'), findsOneWidget);
    expect(tester.getRect(tile('계정')).top, tester.getRect(find.text('계정·정보')).bottom + 8);
    expect(tester.getRect(tile('계정')).bottom, tester.getRect(tile('알림')).top);
    expect(icon3d(tester, '계정').icon, AppIcon3d.userRound);
    expect(find.descendant(of: tile('계정'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"친구 초대" 줄은 하트 카드 마지막 72 줄, 3D 사용자 24 · 셰브런 · 설명 줄이 있다(pen lMDpY b1fvA · mDrtC)', (tester) async {
    await pump(tester);

    expect(tile('친구 초대'), findsOneWidget);
    expect(find.descendant(of: tile('친구 초대'), matching: find.text('내 추천 코드를 친구에게 보내요')), findsOneWidget);
    expect(tester.getSize(tile('친구 초대')).height, 72);
    expect(icon3d(tester, '친구 초대').icon, AppIcon3d.users);
    expect(icon3d(tester, '친구 초대').size, 24);
    expect(divider(tester, '친구 초대'), BorderSide.none);
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

  testWidgets('"차단 목록" 줄은 알림 바로 아래, 3D 차단 아이콘이다(pen lMDpY o0km6 · Dsuwe)', (tester) async {
    await pump(tester);

    expect(tile('차단 목록'), findsOneWidget);
    expect(tester.getRect(tile('차단 목록')).top, tester.getRect(tile('알림')).bottom);
    expect(icon3d(tester, '차단 목록').icon, AppIcon3d.blockUser);
    expect(find.descendant(of: tile('차단 목록'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"차단 목록" 을 누르면 16f 차단 목록이 열린다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('차단 목록'));
    await tester.pumpAndSettle();

    expect(find.byType(BlockListScreen), findsOneWidget);
  });

  testWidgets('"연락처 차단" 줄은 차단 목록 바로 아래 카드 마지막 줄, 3D 연락처 아이콘이다(pen lMDpY eGPnB · Cf6JI)', (tester) async {
    await pump(tester);

    expect(tile('연락처 차단'), findsOneWidget);
    expect(tester.getRect(tile('연락처 차단')).top, tester.getRect(tile('차단 목록')).bottom);
    expect(icon3d(tester, '연락처 차단').icon, AppIcon3d.contact);
    expect(divider(tester, '연락처 차단'), BorderSide.none);
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

  testWidgets('"자주 묻는 질문" 줄은 지원 카드 첫 줄, 3D 도움말 22 와 셰브런이다(pen lMDpY l1K4Xa · fmONi)', (tester) async {
    await pump(tester);

    expect(tester.getRect(tile('자주 묻는 질문')).top, tester.getRect(find.text('지원')).bottom + 8);
    expect(icon3d(tester, '자주 묻는 질문').icon, AppIcon3d.help);
    expect(icon3d(tester, '자주 묻는 질문').size, 22);
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
    expect(tester.getRect(tile('이용약관')).top, tester.getRect(find.text('지원')).bottom + 8);
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

  testWidgets('"로그아웃" 줄은 개인정보처리방침 아래 지원 카드 마지막 줄, 3D 로그아웃 아이콘과 셰브런이다(pen lMDpY ErFPL · Pp2tM)', (tester) async {
    await pump(tester);

    expect(tile('로그아웃'), findsOneWidget);
    expect(tester.getRect(tile('로그아웃')).top, tester.getRect(tile('개인정보처리방침')).bottom);
    expect(icon3d(tester, '로그아웃').icon, AppIcon3d.logout);
    expect(divider(tester, '로그아웃'), BorderSide.none);
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
    // 닫히는 시트는 누름을 아래 화면으로 흘려보낸다 — pump 가 화면을 길게 두어 두 번째 탭 자리 밑에 설정 줄이 오지 않는다.
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
    // button-danger = #E5E5E5 채움 · #C13515 글자 · 52 · 모서리 14 · 16/700(HE8FZ 2026-10-01 개편, 옛 DESIGN §8.3 56).
    expect(tester.widget<AppButton>(button).variant, AppButtonVariant.danger);
    expect(find.ancestor(of: find.text('탈퇴하기'), matching: find.byType(ListTile)), findsNothing);
    // VmUvb padding [24,16,28,16].
    expect(tester.getRect(button).top, tester.getRect(tile('로그아웃')).bottom + 24);
    expect(tester.getRect(button).left, 16);
    expect(tester.getSize(button).height, 52);
    // 아래 28 — 위험 영역 틀(Padding)의 바닥이 버튼 바닥보다 28 아래다.
    final zone = find.ancestor(of: button, matching: find.byType(Padding)).first;
    expect(tester.getRect(zone).bottom - tester.getRect(button).bottom, 28);
  });

  testWidgets('"탈퇴하기"를 누르면 16c 1차 시트가 뜬다', (tester) async {
    await pump(tester);

    // 화면이 짧은 폰에선 버튼이 접힘 아래에 있다 — 밀어서 보이게 한 뒤 누른다.
    await tester.ensureVisible(find.text('탈퇴하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탈퇴하기'));
    await tester.pumpAndSettle();

    expect(find.byType(WithdrawFirstSheet), findsOneWidget);
  });

  testWidgets('"무료로 하트 모으기" 줄은 하트 카드 둘째 줄 · 하트 충전 바로 아래 · 친구 초대 바로 위, 3D 선물 24 와 셰브런이다(pen lMDpY oNgRd · oBpe4)', (tester) async {
    await pump(tester);

    expect(tile('무료로 하트 모으기'), findsOneWidget);
    expect(tester.getRect(tile('무료로 하트 모으기')).top, tester.getRect(tile('하트 충전')).bottom);
    expect(tester.getRect(tile('무료로 하트 모으기')).bottom, tester.getRect(tile('친구 초대')).top);
    expect(icon3d(tester, '무료로 하트 모으기').icon, AppIcon3d.gift);
    expect(find.descendant(of: tile('무료로 하트 모으기'), matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
  });

  testWidgets('"무료로 하트 모으기" 를 누르면 18a 로 간다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('무료로 하트 모으기'));
    await tester.pumpAndSettle();

    expect(find.text('18a'), findsOneWidget);
  });

  testWidgets('맨 위 보유 하트 블록 다음에 매칭 · 하트 · 계정·정보 · 지원 순, 머리글 14/700 #6A6A6A 아래 8 에 카드, 섹션 사이 20, 목록 여백 위 12 · 좌우 16(pen HM9xA · BOxgn)', (tester) async {
    await pump(tester);

    for (final header in ['매칭', '하트', '계정·정보', '지원']) {
      final style = tester.renderObject<RenderParagraph>(find.text(header)).text.style!;
      expect(style.fontSize, 14);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.color, AppColors.muted);
    }
    // 목록 맨 위 안쪽 여백 12 뒤에 보유 하트 블록(높이 64)이 오고, 다음 섹션까지 20(pen `HM9xA` gap 20 · `X4olk`).
    expect(tester.getTopLeft(find.text('매칭')), const Offset(16, 56 + 12 + 64 + 20));
    expect(tester.getRect(tile('매칭 활성화')).top, tester.getRect(find.text('매칭')).bottom + 8);
    expect(tester.getRect(find.text('하트')).top, tester.getRect(tile('매칭 활성화')).bottom + 20);
    expect(tester.getRect(tile('하트 충전')).top, tester.getRect(find.text('하트')).bottom + 8);
    expect(tester.getRect(find.text('계정·정보')).top, tester.getRect(tile('친구 초대')).bottom + 20);
    expect(tester.getRect(find.text('지원')).top, tester.getRect(tile('연락처 차단')).bottom + 20);
  });

  testWidgets('카드는 #F7F7F7 · 모서리 12 · 테두리 #DDDDDD 1, 줄은 카드 폭 그대로(pen k2pmUO · LkmNK)', (tester) async {
    await pump(tester);

    final card = find.ancestor(of: tile('계정'), matching: find.byType(Container)).first;
    final container = tester.widget<Container>(card);
    final fill = container.decoration! as BoxDecoration;
    expect(fill.color, AppColors.surfaceSoft);
    expect(fill.borderRadius, BorderRadius.circular(AppRadius.input));
    final outline = container.foregroundDecoration! as BoxDecoration;
    expect(outline.border, Border.all(color: AppColors.hairline));
    expect(container.clipBehavior, Clip.antiAlias);
    expect(tester.getRect(card).left, 16);
    expect(tester.getRect(tile('계정')).width, tester.getRect(card).width);
  });

  testWidgets('줄은 52 · 좌우 14 · 아이콘 24 → 12 → 제목 16/400 #222222, 셰브런 20 #6A6A6A, 아래 선 #EBEBEB(pen K4uiNp)', (tester) async {
    await pump(tester);

    final row = tester.getRect(tile('알림'));
    expect(row.height, 52);
    final icon = find.descendant(of: tile('알림'), matching: find.byType(Icon3d));
    expect(tester.widget<Icon3d>(icon).icon, AppIcon3d.bell);
    expect(tester.getSize(icon), const Size(24, 24));
    expect(tester.getTopLeft(icon).dx, row.left + 14);
    expect(tester.getCenter(icon).dy, row.center.dy);
    expect(tester.getTopLeft(find.text('알림')).dx, row.left + 14 + 24 + 12);
    final title = tester.renderObject<RenderParagraph>(find.text('알림')).text.style!;
    expect(title.fontSize, 16);
    expect(title.fontWeight, FontWeight.w400);
    expect(title.color, AppColors.ink);
    final chevron = find.descendant(of: tile('알림'), matching: find.byIcon(AppIcons.chevronRight));
    expect(tester.getSize(chevron), const Size(20, 20));
    expect(tester.widget<Icon>(chevron).color, AppColors.muted);
    expect(tester.getTopRight(chevron).dx, row.right - 14);
    expect(divider(tester, '알림'), const BorderSide(color: AppColors.hairlineSoft));
  });

  testWidgets('매칭 활성화는 72 줄, 3D 사용자 22, 설명 12 #6A6A6A(pen TLrmq · vBzsu)', (tester) async {
    await pump(tester);

    expect(tester.getSize(tile('매칭 활성화')).height, 72);
    expect(icon3d(tester, '매칭 활성화').icon, AppIcon3d.users);
    expect(icon3d(tester, '매칭 활성화').size, 22);
    final note = tester.renderObject<RenderParagraph>(find.text('잠시 쉬고 싶으면 꺼두세요')).text.style!;
    expect(note.fontSize, 12);
    expect(note.color, AppColors.muted);
  });

  testWidgets('"이용약관" · "개인정보처리방침" 은 FAQ 와 로그아웃 사이, 3D 약관 · 개인정보 아이콘이다(A6, pen F4pb9 · yEBjk)', (tester) async {
    await pump(tester);

    expect(tester.getRect(tile('이용약관')).top, tester.getRect(tile('자주 묻는 질문')).bottom);
    expect(tester.getRect(tile('개인정보처리방침')).top, tester.getRect(tile('이용약관')).bottom);
    expect(icon3d(tester, '이용약관').icon, AppIcon3d.terms);
    expect(icon3d(tester, '개인정보처리방침').icon, AppIcon3d.privacy);
    expect(divider(tester, '개인정보처리방침'), const BorderSide(color: AppColors.hairlineSoft));
  });

  testWidgets('"이용약관" 은 약관 1부, "개인정보처리방침" 은 약관 페이지를 기기 브라우저로 연다(대장 10-03 나)', (tester) async {
    await pump(tester);

    await tester.tap(find.text('이용약관'));
    await tester.pump();
    await tester.tap(find.text('개인정보처리방침'));
    await tester.pump();

    expect(opened, [termsLink, privacyPolicyLink]);
    expect(find.byType(AppToast), findsNothing);
  });

  testWidgets('약관을 못 열면 안내 토스트를 띄우고 설정에 남는다', (tester) async {
    await pump(tester);
    openUrl = (_) async => throw Exception('no browser');

    await tester.tap(find.text('이용약관'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AppToast), findsOneWidget);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  group('보유 하트 블록(pen X4olk) · "하트 충전" 줄(pen zlpeY)', () {
    Finder block() => find.ancestor(of: find.text('보유 하트'), matching: find.byType(Material)).first;
    Finder store() => find.text('18 스토어');
    Future<void> penFrame(WidgetTester tester, {double scale = 1.0}) async {
      tester.view.physicalSize = const Size(360, 1102) * tester.view.devicePixelRatio; // pen `lMDpY` 360×1102
      if (scale != 1.0) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      await tester.pumpAndSettle();
    }

    testWidgets('목록 맨 위(위 여백 12 · 좌우 16 · 폭 328 · 높이 64) · #FFF0F2 · 모서리 12 · 테두리 · 그림자 없음', (tester) async {
      await pump(tester);
      await penFrame(tester);

      final rect = tester.getRect(block());
      expect(rect.topLeft, const Offset(16, 56 + 12));
      expect((rect.width, rect.height), (328, 64));
      final material = tester.widget<Material>(block());
      expect(material.color, AppColors.primaryWash);
      expect(material.borderRadius, BorderRadius.circular(AppRadius.input));
      expect(material.shape, isNull);
      expect(material.elevation, 0);
      expect(find.descendant(of: block(), matching: find.byType(DecoratedBox)), findsNothing); // 테두리 · 그림자 없음
      expect(tester.getTopLeft(find.text('매칭')).dy, rect.bottom + 20);
    });

    testWidgets('안쪽: 하트 그림 28 → 10 → 세로(보유 하트 · 숫자, 사이 2) → 10 → 충전 → 10 → 셰브런 20, 안쪽 좌우 16', (tester) async {
      await pump(tester);
      await penFrame(tester);

      final rect = tester.getRect(block());
      final heart = find.descendant(of: block(), matching: find.byType(Image));
      expect((tester.widget<Image>(heart).image as AssetImage).assetName, 'assets/images/heart-flat-vector-v3.png');
      expect(tester.getSize(heart), const Size(28, 28));
      expect(tester.getTopLeft(heart).dx, rect.left + 16);
      expect(tester.getCenter(heart).dy, rect.center.dy);
      expect(tester.getTopLeft(find.text('보유 하트')).dx, tester.getTopRight(heart).dx + 10);
      expect(tester.getTopLeft(find.text('320개')).dx, tester.getTopLeft(find.text('보유 하트')).dx); // 왼쪽 정렬
      final chevron = find.descendant(of: block(), matching: find.byIcon(AppIcons.chevronRight));
      expect(tester.getSize(chevron), const Size(20, 20));
      expect(tester.getTopRight(chevron).dx, rect.right - 16);
      expect(tester.getTopRight(find.text('충전')).dx + 10, tester.getTopLeft(chevron).dx);
      expect(tester.getCenter(find.text('충전')).dy, rect.center.dy);
      expect(tester.getCenter(chevron).dy, rect.center.dy);
      // 위 글자와 숫자 사이 2 는 줄 높이 안쪽 여백이 있어 글자 상자 사이로 잰다.
      final column = tester.getRect(find.ancestor(of: find.text('보유 하트'), matching: find.byType(Column)).first);
      expect(tester.getCenter(find.byWidget(tester.widget(find.ancestor(of: find.text('보유 하트'), matching: find.byType(Column)).first))).dy,
          closeTo(rect.center.dy, 0.6));
      expect(column.height, closeTo(tester.getSize(find.text('보유 하트')).height + 2 + tester.getSize(find.text('320개')).height, 0.6));
    });

    testWidgets('글자: 보유 하트 14/600 #6A6A6A · 숫자 20/700 #222222 · 충전 14/700 #C4224B · 셰브런 #C4224B', (tester) async {
      await pump(tester);
      await penFrame(tester);

      TextStyle style(String text) => tester.renderObject<RenderParagraph>(find.text(text)).text.style!;
      expect((style('보유 하트').fontSize, style('보유 하트').fontWeight, style('보유 하트').color), (14, FontWeight.w600, AppColors.muted));
      expect((style('320개').fontSize, style('320개').fontWeight, style('320개').color), (20, FontWeight.w700, AppColors.ink));
      expect((style('충전').fontSize, style('충전').fontWeight, style('충전').color), (14, FontWeight.w700, AppColors.primaryText));
      final chevron = find.descendant(of: block(), matching: find.byIcon(AppIcons.chevronRight));
      expect(tester.widget<Icon>(chevron).color, AppColors.primaryText);
    });

    testWidgets('숫자는 서버 값을 "N개" 로 — 1,000 이상은 쉼표, 0 도 그대로', (tester) async {
      await pump(tester, profile: Success(_profile(1250)));
      await tester.pump();
      expect(find.text('1,250개'), findsOneWidget);

      await pump(tester, profile: Success(_profile(0)));
      await tester.pump();
      expect(find.text('0개'), findsOneWidget);
    });

    testWidgets('[pen 에 없는 상태] 읽는 중에는 숫자 자리에 "-" 를 두고 블록 · 높이는 그대로, 값이 오면 바뀐다', (tester) async {
      final gate = Completer<void>();
      await pump(tester, profileGate: gate.future);
      await penFrame(tester);

      expect(find.text('-'), findsOneWidget);
      expect(tester.getSize(block()), const Size(328, 64));
      final matchingTop = tester.getTopLeft(find.text('매칭')).dy;

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('320개'), findsOneWidget);
      expect(find.text('-'), findsNothing);
      expect(tester.getTopLeft(find.text('매칭')).dy, matchingTop); // 아래 줄이 밀리지 않는다
    });

    testWidgets('[pen 에 없는 상태] 읽기에 실패하면 "-" 이고 눌러서 스토어는 열린다', (tester) async {
      await pump(tester, profile: const FailureResult(NetworkFailure()));
      await tester.pump();

      expect(find.text('-'), findsOneWidget);
      await tester.tap(find.text('충전'));
      await tester.pumpAndSettle();
      expect(store(), findsOneWidget);
    });

    testWidgets('블록 어디를 눌러도(글자 · 그림 · 셰브런 · 가장자리) 하트 스토어로 간다', (tester) async {
      for (final target in <Finder Function()>[
        () => find.text('보유 하트'),
        () => find.text('320개'),
        () => find.text('충전'),
        () => find.descendant(of: block(), matching: find.byType(Image)),
        () => find.descendant(of: block(), matching: find.byIcon(AppIcons.chevronRight)),
      ]) {
        await pump(tester);
        await tester.pump();
        await tester.tap(target());
        await tester.pumpAndSettle();
        expect(store(), findsOneWidget);
      }
    });

    testWidgets('"하트 충전" 줄을 눌러도 하트 스토어로 간다', (tester) async {
      await pump(tester);

      await tester.tap(find.text('하트 충전'));
      await tester.pumpAndSettle();

      expect(store(), findsOneWidget);
    });

    testWidgets('블록과 줄을 프레임 없이 연달아 눌러도 스토어는 한 겹이고, 닫으면 다시 열 수 있다', (tester) async {
      await pump(tester);
      await tester.pump();

      await tester.tap(find.text('충전'));
      await tester.tap(find.text('하트 충전')); // 첫 누름이 만든 길이 아직 그려지기 전
      await tester.pumpAndSettle();
      expect(store(), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(store(), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget); // 한 번 닫으면 설정이다(두 겹이면 스토어가 남는다)

      await tester.tap(find.text('하트 충전'));
      await tester.pumpAndSettle();
      expect(store(), findsOneWidget);
    });

    testWidgets('"하트 충전" 줄은 하트 카드 첫 줄 — 52 · 안쪽 14 · lucide plus 20 #3F3F3F → 12 → 16/400 #222222 · 셰브런 20 #6A6A6A · 아래 선 #EBEBEB', (tester) async {
      await pump(tester);

      final row = tester.getRect(tile('하트 충전'));
      expect(row.height, 52);
      expect(row.top, tester.getRect(find.text('하트')).bottom + 8);
      final plus = find.descendant(of: tile('하트 충전'), matching: find.byIcon(AppIcons.plus));
      expect(tester.getSize(plus), const Size(20, 20));
      expect(tester.widget<Icon>(plus).color, AppColors.body);
      expect(tester.getTopLeft(plus).dx, row.left + 14);
      expect(find.descendant(of: tile('하트 충전'), matching: find.byType(Icon3d)), findsNothing); // 3D 아이콘이 아니다
      expect(tester.getTopLeft(find.text('하트 충전')).dx, row.left + 14 + 20 + 12);
      final title = tester.renderObject<RenderParagraph>(find.text('하트 충전')).text.style!;
      expect((title.fontSize, title.fontWeight, title.color), (16, FontWeight.w400, AppColors.ink));
      final chevron = find.descendant(of: tile('하트 충전'), matching: find.byIcon(AppIcons.chevronRight));
      expect(tester.widget<Icon>(chevron).color, AppColors.muted);
      expect(tester.getTopRight(chevron).dx, row.right - 14);
      expect(divider(tester, '하트 충전'), const BorderSide(color: AppColors.hairlineSoft));
    });

    testWidgets('스크린리더: 블록은 "보유 하트 320개, 충전" 한 덩어리 버튼', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await tester.pump();

      final data = tester.getSemantics(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '보유 하트 320개, 충전')).getSemanticsData();
      expect(data.label, '보유 하트 320개, 충전');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('누름 칸은 안드로이드 터치 영역(48×48) 기준을 지킨다(블록 64 · 줄 52)', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await tester.pump();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('눌림 효과는 블록 안에서 그려진다(COMMON §4-2) — 잉크가 블록 Material 위다', (tester) async {
      await pump(tester);
      final controller = Material.of(tester.element(find.descendant(of: block(), matching: find.byType(InkWell))));
      expect(controller, isNot(paints..rrect()));

      final gesture = await tester.startGesture(tester.getCenter(find.text('충전')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller, paints..rrect());
      expect(tester.getRect(find.descendant(of: block(), matching: find.byType(InkWell))), tester.getRect(block()));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('글자 배율 $scale 에서도 넘치지 않고 높이는 64 이상으로 늘어나며 글자가 잘리지 않는다', (tester) async {
        await pump(tester);
        await penFrame(tester, scale: scale);

        expect(tester.takeException(), isNull);
        expect(tester.getSize(block()).height, greaterThanOrEqualTo(64));
        for (final text in ['보유 하트', '320개', '충전']) {
          final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
          expect(paragraph.getMaxIntrinsicHeight(paragraph.size.width), lessThanOrEqualTo(paragraph.size.height + 0.5), reason: text);
          expect(paragraph.getMinIntrinsicWidth(double.infinity), lessThanOrEqualTo(paragraph.size.width + 0.5), reason: text);
        }
      });
    }
  });

  testWidgets('360 폭 · 2.0배에서도 넘치지 않는다', (tester) async {
    await pump(tester);
    tester.view.physicalSize = const Size(360, 1400) * tester.view.devicePixelRatio;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
