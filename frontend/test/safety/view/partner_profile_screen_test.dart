import 'dart:async';
import 'dart:typed_data';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/photo_slider.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/safety/model/safety_repository_provider.dart';
import 'package:campus_mate/safety/view/partner_profile_screen.dart';
import 'package:campus_mate/safety/view/report_sheet.dart';
import 'package:campus_mate/safety/viewmodel/report_ui_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../model/fake_safety_repository.dart';

// 1×1 투명 PNG(photo_slider_test 와 같은 바이트). 테스트는 네트워크 대신 이 그림을 쓴다.
const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
];

final _memoryPhotos = partnerPhotoImageProvider.overrideWithValue((url) => MemoryImage(Uint8List.fromList(_png)));

/// 슬라이더의 사진 칸(그림을 decoration 으로 깐 상자).
final _photo = find.byWidgetPredicate(
  (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).image != null,
);

/// 세로로 내리는 화면 스크롤. 사진 슬라이더(가로 PageView)도 Scrollable 이라 이름으로 골라야 한다.
final _page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);

/// "이런 사람이 좋아요" 글. 360 폭에서도 두 줄 넘게 감기는 길이다.
const _idealNote = '주말에 같이 산책하고 맛집을 찾아다니는 걸 좋아하는 사람이면 좋겠어요. 대화가 잘 통하면 더 좋아요.';

/// 14c 상대 프로필 상세(pen `VTX3D`). 신고 · 차단 결과는 채팅방(chat_room_safety_test)과 같아야 한다.
void main() {
  late FakeSafetyRepository safety;
  late FakeChatRepository chat;

  setUp(() {
    safety = FakeSafetyRepository()
      ..partnerProfile = Success(partnerProfileFixture(kakaoId: 'fox_rain', photoUrls: const ['https://x/1.jpg']));
    chat = FakeChatRepository();
  });

  /// [pushed] 면 앞 화면 위에 push 로 연다(채팅방 14b 버튼과 같다). 아니면 `go` 로 바로 연다.
  Future<GoRouter> pump(WidgetTester tester, {bool pushed = true, double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(
      overrides: [
        safetyRepositoryProvider.overrideWithValue(safety),
        chatRepositoryProvider.overrideWithValue(chat),
        _memoryPhotos,
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: pushed ? '/room' : '${AppRoutes.partnerProfile}/p2',
      routes: [
        GoRoute(path: '/room', builder: (context, state) => const Scaffold(body: Text('채팅방'))),
        GoRoute(
          path: AppRoutes.conversations,
          builder: (context, state) => const Scaffold(body: Text('대화 목록')),
        ),
        GoRoute(
          path: '${AppRoutes.partnerProfile}/:profileId',
          builder: (context, state) => PartnerProfileScreen(profileId: state.pathParameters['profileId']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    if (pushed) {
      unawaited(router.push('${AppRoutes.partnerProfile}/p2'));
    }
    await tester.pumpAndSettle();
    return router;
  }

  Finder link(String label) => find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

  Future<void> tapLink(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(find.text(label), 300, scrollable: _page);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('게이트 뒤(서로 수락)', () {
    testWidgets('앱바는 "{닉} 님 프로필", 본문은 10b 와 같은 카드 한 장이다', (tester) async {
      await pump(tester);

      expect(find.text('여우비 님 프로필'), findsOneWidget);
      expect(find.byType(ProfileCard), findsOneWidget);
      expect(safety.partnerProfileRequests, ['p2']);
      // 결정 바(거절 · 수락)와 지인 리뷰는 없다.
      expect(find.text('수락하기'), findsNothing);
      expect(find.text('지인 리뷰'), findsNothing);
    });

    testWidgets('신뢰 배지는 이름 줄 오른쪽 — badge-check 15 + 14/600, 간격 5(pen N3WijU)', (tester) async {
      await pump(tester);

      final icon = tester.widget<Icon>(find.byIcon(AppIcons.badgeCheck));
      expect(icon.size, 15);
      expect(icon.color, AppColors.primaryText);
      final label = tester.getRect(find.text('신뢰 확인 완료'));
      expect(label.left - tester.getRect(find.byIcon(AppIcons.badgeCheck)).right, 5);
      expect(label.height, 20);
      final card = tester.getRect(find.byType(ProfileCard));
      expect(label.right, card.right - 21);
      expect(label.center.dy, closeTo(tester.getRect(find.text('여우비, 23')).center.dy, 0.5));
    });

    testWidgets('카카오 카드(pen tLtXl) — 높이 64, 여백 [12,14], 복사 아이콘 18 · 누르는 영역 48', (tester) async {
      await pump(tester);
      await tester.scrollUntilVisible(find.text('fox_rain'), 300, scrollable: _page);

      final box = find.ancestor(of: find.text('카카오톡 아이디'), matching: find.byType(Container)).first;
      final kakao = tester.getRect(box);
      expect(kakao.height, 64);
      final label = tester.getRect(find.text('카카오톡 아이디'));
      expect(label.top - kakao.top, 12);
      expect(label.left - kakao.left, 14);
      expect(label.height, 16);
      final value = tester.getRect(find.text('fox_rain'));
      expect(value.top - label.bottom, 2);
      expect(value.height, 22);
      final copy = tester.getRect(find.byIcon(AppIcons.copy));
      expect(copy.size, const Size(18, 18));
      expect(kakao.right - copy.right, 14);
      expect(copy.center.dy, kakao.center.dy);
      expect(tester.widget<Icon>(find.byIcon(AppIcons.copy)).color, AppColors.primaryText);
      final copyButton = find.ancestor(of: find.byIcon(AppIcons.copy), matching: find.byType(IconButton));
      expect(tester.getSize(copyButton), const Size(48, 48));
    });

    testWidgets('링크 줄(pen divm8) — 구분선 아래 11, 카드 아래 끝까지 20, 회색 14', (tester) async {
      await pump(tester);
      await tester.scrollUntilVisible(find.text('차단하기'), 300, scrollable: _page);

      final card = tester.getRect(find.byType(ProfileCard));
      final report = tester.getRect(find.text('신고하기'));
      final block = tester.getRect(find.text('차단하기'));
      expect(report.height, 20);
      expect(block.top, report.top);
      // 테두리 1 + 보이는 간격 20.
      expect(card.bottom - report.bottom, 21);
      final divider = tester.getRect(find.byType(Divider).last);
      expect(report.top - divider.bottom, 11);
      // 카카오 카드 아래 1 뒤에 구분선.
      final kakao = tester.getRect(find.ancestor(of: find.text('카카오톡 아이디'), matching: find.byType(Container)).first);
      expect(divider.top - kakao.bottom, 1);
      expect(tester.getRect(find.byIcon(AppIcons.flag)).size, const Size(14, 14));
      expect(tester.getRect(find.byIcon(AppIcons.ban)).size, const Size(14, 14));
      expect(report.left - tester.getRect(find.byIcon(AppIcons.flag)).right, 6);
      final style = tester.widget<Text>(find.text('신고하기')).style!;
      expect(style.color, AppColors.muted);
      expect(style.fontSize, 14);
      expect(tester.widget<Text>(find.text('·')).style!.color, AppColors.hairline);
    });

    testWidgets('링크는 보이는 줄 20 그대로 두고 누르는 영역은 48 이상, 눌림 효과는 링크 안 Material 에 그린다', (tester) async {
      await pump(tester);
      await tester.scrollUntilVisible(find.text('차단하기'), 300, scrollable: _page);

      for (final label in ['신고하기', '차단하기']) {
        final ink = link(label);
        expect(tester.getSize(ink).height, greaterThanOrEqualTo(48), reason: label);
        expect(tester.getSize(ink).width, greaterThanOrEqualTo(48), reason: label);
        // COMMON §4-2: 가장 가까운 Material 이 화면이 아니라 이 칸이어야 스크롤해도 눌림 효과가 따라간다.
        final material = find.ancestor(of: ink, matching: find.byType(Material)).first;
        expect(tester.getSize(material), tester.getSize(ink), reason: label);
      }
    });
  });

  group('실사진 슬라이더(게이트 뒤에만)', () {
    const twoPhotos = ['https://x/1.jpg', 'https://x/2.jpg'];

    testWidgets('게이트 뒤 사진이 있으면 카드 맨 위에 288×260 슬라이더 하나, 사진 수만큼 장이 있다', (tester) async {
      safety.partnerProfile = Success(partnerProfileFixture(kakaoId: 'fox_rain', photoUrls: twoPhotos));
      await pump(tester);

      expect(find.byType(PhotoSlider), findsOneWidget);
      final slider = tester.widget<PhotoSlider>(find.byType(PhotoSlider));
      expect(slider.photos, hasLength(2));
      expect(slider.photoSize, const Size(288, 260));
      // 값표 14c 에 배지가 없다. 화면 15 "수락 후 공개" 는 게이트 전 뜻이라 게이트 뒤 14c 에 맞지 않는다.
      expect(slider.firstPhotoBadge, isNull);
    });

    test('앱에서는 서명 URL 을 그대로 NetworkImage 로 그린다(테스트만 바꿔 끼운다)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(partnerPhotoImageProvider)('https://x/1.jpg'), const NetworkImage('https://x/1.jpg'));
    });

    testWidgets('게이트 전이면 슬라이더가 없다', (tester) async {
      safety.partnerProfile = Success(partnerProfileFixture());
      await pump(tester);

      expect(find.byType(PhotoSlider), findsNothing);
    });

    testWidgets('게이트 뒤라도 사진이 0장이면 슬라이더가 없다', (tester) async {
      safety.partnerProfile = Success(partnerProfileFixture(kakaoId: 'fox_rain', photoUrls: const []));
      await pump(tester);

      expect(find.byType(PhotoSlider), findsNothing);
      expect(find.text('신뢰 확인 완료'), findsOneWidget);
    });

    // 카드 안쪽 폭은 360 화면에서 286(328 - 테두리 2 - 여백 40)이라 pen 안쪽 288 보다 2 좁다.
    for (final scale in [1.0, 2.0]) {
      testWidgets('360 폭 · 배율 $scale 에서 사진이 카드 안쪽 폭을 꽉 채우고 넘치지 않는다', (tester) async {
        safety.partnerProfile = Success(partnerProfileFixture(kakaoId: 'fox_rain', photoUrls: twoPhotos));
        await pump(tester, scale: scale);

        expect(tester.takeException(), isNull);
        // 테두리 1 + 여백 20.
        final inner = tester.getRect(find.byType(ProfileCard)).deflate(21);
        expect(inner.width, 286);
        final slider = tester.getRect(find.byType(PhotoSlider));
        expect(slider.topLeft, inner.topLeft);
        expect(slider.right, lessThanOrEqualTo(inner.right));
        final photo = tester.getRect(_photo.first);
        expect(photo.height, 260);
        expect(inner.expandToInclude(photo), inner);
        // 안쪽 폭이 사진 + 간격 8 보다 좁으면 오른쪽 간격 없이 꽉 채운다(통합대장 09-27) — 좌우 여백이 같다.
        expect(photo.width, inner.width);
        expect(photo.left - inner.left, inner.right - photo.right);
        // 값표에 없는 값 — 카드 안 섹션 간격 13(pen `TORAs`)을 따랐다.
        expect(tester.getRect(find.text('여우비, 23')).top - slider.bottom, 13);
      });
    }
  });

  testWidgets('게이트 전이면 배지와 카카오 카드가 없다', (tester) async {
    safety.partnerProfile = Success(partnerProfileFixture());
    await pump(tester);

    expect(find.text('신뢰 확인 완료'), findsNothing);
    expect(find.text('카카오톡 아이디'), findsNothing);
    await tester.scrollUntilVisible(find.text('신고하기'), 300, scrollable: _page);
    expect(find.text('차단하기'), findsOneWidget);
  });

  // pen `VTX3D` 에는 이 칸이 없다 — 10b 카드 값을 따른다(사용자 (가), 통합대장 09-27).
  // 카드의 다른 마지막 칸은 섹션 간격 13(pen `TORAs`)을 달고 끝나니 footer 도 그 13 뒤에 온다.
  group('"이런 사람이 좋아요" 글 아래 간격', () {
    Rect kakaoRect(WidgetTester tester) =>
        tester.getRect(find.ancestor(of: find.text('카카오톡 아이디'), matching: find.byType(Container)).first);

    testWidgets('게이트 뒤 — 글 아래 끝에서 카카오 카드 위 끝까지 13', (tester) async {
      safety.partnerProfile = Success(
        partnerProfileFixture(kakaoId: 'fox_rain', photoUrls: const ['https://x/1.jpg'], idealNote: _idealNote),
      );
      await pump(tester);
      await tester.scrollUntilVisible(find.text('fox_rain'), 300, scrollable: _page);

      expect(find.text('이런 사람이 좋아요'), findsOneWidget);
      expect(kakaoRect(tester).top - tester.getRect(find.text(_idealNote)).bottom, 13);
    });

    testWidgets('게이트 전 — 글 아래 끝에서 구분선 위 끝까지 13', (tester) async {
      safety.partnerProfile = Success(partnerProfileFixture(idealNote: _idealNote));
      await pump(tester);
      await tester.scrollUntilVisible(find.text('신고하기'), 300, scrollable: _page);

      final divider = tester.getRect(find.byType(Divider).last);
      expect(divider.top - tester.getRect(find.text(_idealNote)).bottom, 13);
    });

    testWidgets('글이 없으면 자리는 그대로 — 마지막 태그 칸(이상형 특징) 뒤 13 에 구분선', (tester) async {
      safety.partnerProfile = Success(partnerProfileFixture());
      await pump(tester);
      await tester.scrollUntilVisible(find.text('신고하기'), 300, scrollable: _page);

      expect(find.text('이런 사람이 좋아요'), findsNothing);
      final lastTags = tester.getRect(find.ancestor(of: find.text('다정한'), matching: find.byType(Wrap)).first);
      expect(tester.getRect(find.byType(Divider).last).top - lastTags.bottom, 13);
    });
  });

  group('신고 · 차단(채팅방과 같은 결과)', () {
    testWidgets('신고하면 토스트를 띄우고 대화 목록을 새로 읽어 목록으로 간다', (tester) async {
      await pump(tester);
      final fetchesBefore = chat.conversationsFetchCount;

      await tapLink(tester, '신고하기');
      expect(find.byType(ReportSheet), findsOneWidget);
      await tester.tap(find.text('광고·스팸'));
      await tester.pump();
      await tester.tap(find.text('신고하기').last);
      await tester.pumpAndSettle();

      expect(safety.reports.single.target, {'target_type': 'profile', 'target_id': 'p2'});
      expect(find.text('대화 목록'), findsOneWidget);
      expect(find.text(reportedMessage), findsOneWidget);
      expect(chat.conversationsFetchCount, greaterThan(fetchesBefore));
    });

    testWidgets('이미 신고했으면 역시 목록으로 간다', (tester) async {
      safety.reportResult = const FailureResult(ServerRejectedFailure('이미 신고한 사용자예요'));
      await pump(tester);

      await tapLink(tester, '신고하기');
      await tester.tap(find.text('광고·스팸'));
      await tester.pump();
      await tester.tap(find.text('신고하기').last);
      await tester.pumpAndSettle();

      expect(find.text('대화 목록'), findsOneWidget);
    });

    testWidgets('하루 상한이면 토스트만 띄우고 14c 에 남는다', (tester) async {
      safety.reportResult = const FailureResult(RateLimitedFailure());
      await pump(tester);

      await tapLink(tester, '신고하기');
      await tester.tap(find.text('광고·스팸'));
      await tester.pump();
      await tester.tap(find.text('신고하기').last);
      await tester.pumpAndSettle();

      expect(find.byType(PartnerProfileScreen), findsOneWidget);
      expect(find.text('오늘은 더 신고할 수 없어요'), findsOneWidget);
    });

    testWidgets('14e 에서 차단하면 block 을 부르고 대화 목록을 새로 읽어 목록으로 간다', (tester) async {
      await pump(tester);
      final fetchesBefore = chat.conversationsFetchCount;

      await tapLink(tester, '차단하기');
      expect(find.text('여우비 님을 차단할까요?'), findsOneWidget);
      await tester.tap(find.text('차단'));
      await tester.pumpAndSettle();

      expect(safety.blocked, ['p2']);
      expect(find.text('대화 목록'), findsOneWidget);
      expect(chat.conversationsFetchCount, greaterThan(fetchesBefore));
    });

    testWidgets('14e 에서 취소하면 아무것도 하지 않는다', (tester) async {
      await pump(tester);

      await tapLink(tester, '차단하기');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(safety.blocked, isEmpty);
      expect(find.byType(PartnerProfileScreen), findsOneWidget);
    });

    testWidgets('차단이 실패하면 14c 에 남아 실패 문구를 토스트로 알린다', (tester) async {
      safety.blockResult = const FailureResult(NetworkFailure());
      await pump(tester);

      await tapLink(tester, '차단하기');
      await tester.tap(find.text('차단'));
      await tester.pumpAndSettle();

      expect(find.byType(PartnerProfileScreen), findsOneWidget);
      expect(find.widgetWithText(AppToast, '네트워크 연결을 확인해 주세요'), findsOneWidget);
    });
  });

  group('404 · 읽는 중 · 실패', () {
    testWidgets('404 면 빠져나가 앞 화면으로 돌아가고 서버 문구를 짧게 띄운다', (tester) async {
      safety.partnerProfile = const FailureResult(ServerRejectedFailure('프로필을 찾을 수 없어요'));
      await pump(tester);

      expect(find.byType(PartnerProfileScreen), findsNothing);
      expect(find.text('채팅방'), findsOneWidget);
      expect(find.widgetWithText(AppToast, '프로필을 찾을 수 없어요'), findsOneWidget);
    });

    testWidgets('404 인데 돌아갈 화면이 없으면 대화 목록으로 간다', (tester) async {
      safety.partnerProfile = const FailureResult(ServerRejectedFailure('프로필을 찾을 수 없어요'));
      await pump(tester, pushed: false);

      expect(find.text('대화 목록'), findsOneWidget);
    });

    testWidgets('읽는 동안은 도는 표시만 있다', (tester) async {
      safety.holdPartnerProfile = Completer<void>();
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [safetyRepositoryProvider.overrideWithValue(safety), _memoryPhotos],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PartnerProfileScreen(profileId: 'p2')),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ProfileCard), findsNothing);
      safety.holdPartnerProfile!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ProfileCard), findsOneWidget);
    });

    testWidgets('그 밖의 실패는 문구와 "다시 시도" — 누르면 다시 읽는다', (tester) async {
      safety.partnerProfile = const FailureResult(NetworkFailure());
      await pump(tester);

      expect(find.text('네트워크 연결을 확인해 주세요'), findsOneWidget);
      safety.partnerProfile = Success(partnerProfileFixture());
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(safety.partnerProfileRequests, ['p2', 'p2']);
      expect(find.byType(ProfileCard), findsOneWidget);
    });
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0). 넘침(Flex 오류)과 잘림(고정 상자, 오류 없음)을 따로 본다.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
      // 칸이 제일 많은 경우로 본다 — 게이트 뒤(사진 · 배지 · 카카오 카드)에 "이런 사람이 좋아요" 글까지.
      safety.partnerProfile = Success(
        partnerProfileFixture(kakaoId: 'fox_rain', photoUrls: const ['https://x/1.jpg'], idealNote: _idealNote),
      );
      await pump(tester, scale: scale);

      // 카톡 아이디는 끊을 곳이 없는 한 덩어리라 좁으면 글자 단위로 줄을 바꾼다 — 폭 검사에서만 뺀다(높이는 본다).
      List<String> clippedTexts() => [
            for (final element in find.byType(RichText).evaluate())
              if (element.renderObject case final RenderParagraph p
                  when p.getMaxIntrinsicHeight(p.size.width) > p.size.height + 0.5 ||
                      (p.text.toPlainText() != 'fox_rain' &&
                          p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5))
                p.text.toPlainText(),
          ];

      final clipped = clippedTexts();
      await tester.scrollUntilVisible(find.text('차단하기'), 300, scrollable: _page);
      clipped.addAll(clippedTexts());

      expect(tester.takeException(), isNull);
      expect(clipped.toSet(), isEmpty);
    });
  }
}
