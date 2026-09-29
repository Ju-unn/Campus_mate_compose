import 'dart:async';
import 'dart:io';

import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/photo_slider.dart';
import 'package:campus_mate/core/router/app_router.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_elevation.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/model/photo_slot.dart';
import 'package:campus_mate/me/view/basic_info_edit_screen.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/view/me_load_error.dart';
import 'package:campus_mate/me/view/my_photos_screen.dart';
import 'package:campus_mate/me/view/profile_edit_screen.dart';
import 'package:campus_mate/me/view/profile_entry_row.dart';
import 'package:campus_mate/me/view/profile_manage_screen.dart';
import 'package:campus_mate/profile/model/onboarding_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mocktail/mocktail.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../home/model/fake_home_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../model/fake_me_repository.dart';

/// 사진 요청을 받기만 하고 답하지 않는 HttpClient — 화면 15 테스트와 같은 이유(그림은 "아직 오는 중").
class _PendingHttpClient extends Mock implements HttpClient {}

class _PendingHttpOverrides extends HttpOverrides {
  _PendingHttpOverrides(this._client);

  final HttpClient _client;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _client;
}

const _bio = '주말엔 카페 투어와 등산을 즐겨요. 새로운 사람을 만나는 걸 좋아하고, 대화가 잘 통하는 사람을 찾고 있어요.';

/// 이름·학교는 지어낸 값이다.
MyProfile _profile({
  int? heightCm = 178,
  String? mbti = 'ENFP',
  String? major = '경영학과',
  List<String> photoUrls = const ['https://img.test/1.png', 'https://img.test/2.png'],
  int? preferredAgeMin = 22,
  int? preferredAgeMax = 27,
  int? preferredHeightMin = 165,
  int? preferredHeightMax = 180,
  String? bio = _bio,
}) =>
    MyProfile(
      nickname: '여우',
      age: 23,
      university: '가나대학교',
      major: major,
      heightCm: heightCm,
      mbti: mbti,
      avatarUrl: 'https://img.test/avatar.png',
      photos: [
        for (final (index, url) in photoUrls.indexed) MyPhoto(id: 'p-$index', url: url, isAvatarSource: index == 0),
      ],
      preferredAgeMin: preferredAgeMin,
      preferredAgeMax: preferredAgeMax,
      preferredHeightMin: preferredHeightMin,
      preferredHeightMax: preferredHeightMax,
      bio: bio,
    );

final _list = find.byType(Scrollable).first;

/// [url] 그림을 decoration 으로 깐 상자.
Finder _imageBox(String url) => find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).image?.image == NetworkImage(url),
    );

/// [of] 를 품은 카드 — 채움이 흰색이고 그림자가 있는 상자.
Finder _shadowCard({required Finder of}) => find.ancestor(
      of: of,
      matching: find.byWidgetPredicate(
        (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).boxShadow != null,
      ),
    );

/// "수정 ›"(`A8LX2`)의 누름 칸.
final _editLink = find.ancestor(of: find.text('수정 ›'), matching: find.byType(InkWell));

/// 15-5 프로필 편집(pen `rrJ27` 360×1131, 계획서 4절 15-5 표 · A12). 화면 15 에 있던 실사진 · 기본 정보 · 선호 조건 ·
/// 자기소개 테스트를 여기로 옮겨 왔다.
void main() {
  final previousOverrides = HttpOverrides.current;
  setUpAll(() {
    registerFallbackValue(Uri());
    final client = _PendingHttpClient();
    when(() => client.getUrl(any())).thenAnswer((_) => Completer<HttpClientRequest>().future);
    HttpOverrides.global = _PendingHttpOverrides(client);
  });
  tearDownAll(() => HttpOverrides.global = previousOverrides);

  /// 화면 15 자리 위에 15-5 를 올린다. [settle] 이 false 면 첫 프레임(불러오는 중)에서 멈춘다.
  Future<FakeMeRepository> pump(
    WidgetTester tester, {
    Result<MyProfile>? result,
    bool settle = true,
  }) async {
    final repository = FakeMeRepository(result ?? Success(_profile()));
    final container = ProviderContainer(overrides: [meRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.myProfile,
      routes: [
        GoRoute(path: AppRoutes.myProfile, builder: (context, state) => const Scaffold(body: Text('화면 15'))),
        GoRoute(path: AppRoutes.myProfileManage, builder: (context, state) => const ProfileManageScreen()),
        GoRoute(
          path: AppRoutes.myPhotos,
          builder: (context, state) => const Scaffold(body: Text('15-7 사진 수정 화면')),
        ),
        // 15-6 자리 — 저장하면 true, 그냥 나가면 아무것도 돌려주지 않는다(BasicInfoEditScreen 과 같은 약속).
        GoRoute(
          path: AppRoutes.myBasicInfo,
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                const Text('15-6 기본 정보 수정 화면'),
                TextButton(onPressed: () => context.pop(true), child: const Text('15-6 저장')),
                TextButton(onPressed: () => context.pop(), child: const Text('15-6 뒤로')),
              ],
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.myIdealConditions,
          builder: (context, state) => const Scaffold(body: Text('06-1 편집 화면')),
        ),
        GoRoute(
          path: AppRoutes.myProfileEdit,
          builder: (context, state) => const Scaffold(body: Text('15c 편집 화면')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    unawaited(router.push(AppRoutes.myProfileManage));
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
    return repository;
  }

  void usePenFrame(WidgetTester tester, {double height = 780}) {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// ListView 는 아래 칸을 그리기 전엔 끝 길이를 어림한다 — 진짜 끝까지 되풀이한다.
  Future<void> scrollToEnd(WidgetTester tester) async {
    final position = tester.state<ScrollableState>(_list).position;
    do {
      await tester.drag(_list, const Offset(0, -3000));
      await tester.pumpAndSettle();
    } while (position.pixels < position.maxScrollExtent);
  }

  /// 화면 밖(캐시 영역)이면 눌리지 않아 화면 안으로 끌어온다.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200, scrollable: _list);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  group('앱바 `VBRNa` · 틀', () {
    testWidgets('편집 앱바(N14) 제목 "프로필 편집", 뒤로를 누르면 화면 15 로 돌아간다', (tester) async {
      await pump(tester);

      expect(tester.widget<EditAppBar>(find.byType(EditAppBar)).title, '프로필 편집');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('화면 15'), findsOneWidget);
      expect(find.byType(ProfileManageScreen), findsNothing);
    });

    testWidgets('하단 내비와 저장 버튼이 없다(N19 — 화면마다 저장)', (tester) async {
      await pump(tester);

      for (final pass in ['처음', '끝까지 스크롤한 뒤']) {
        expect(find.byType(AppBottomNav), findsNothing, reason: pass);
        expect(find.byType(AppButton), findsNothing, reason: pass);
        expect(find.text('저장'), findsNothing, reason: pass);
        await scrollToEnd(tester);
      }
    });
  });

  group('pen 좌표(배율 1.0, 본문 `H4VWO` 위 24 · 좌우 16 · 섹션 사이 32 · 섹션 안 12)', () {
    testWidgets('섹션 순서 실제 사진 → 기본 정보 → 선호 조건 → 자기소개, 모든 간격', (tester) async {
      // 전부 한 화면에 들어오게 세로만 늘린다.
      usePenFrame(tester, height: 1600);
      await pump(tester);

      final top = tester.getBottomLeft(find.byType(AppBar)).dy;
      expect(top, 56);
      double y(Finder finder) => tester.getTopLeft(finder).dy - top;
      double bottom(Finder finder) => tester.getBottomLeft(finder).dy - top;

      // 실제 사진 `Rn3AC`: 헤더 25 → 12 → 사진 252×184.
      expect(y(find.text('실제 사진')), 24);
      expect(tester.getTopLeft(find.text('실제 사진')).dx, 16);
      final photo = _imageBox('https://img.test/1.png');
      expect(y(photo), 24 + 25 + 12);
      expect(tester.getRect(photo).left, 16);
      expect(tester.getSize(photo), const Size(252, 184));
      // 사진 ↔ 점 12 · 점 → 교체 버튼 12(`Rn3AC` gap 12 한 벌 — 대장 (가) 09-29, PhotoSlider `dotsGap`).
      final replace = find.ancestor(of: find.text('실제 사진 교체'), matching: find.byType(InkWell));
      expect(y(replace), 61 + 184 + 12 + 6 + 12);
      expect(tester.getSize(replace), const Size(328, 44));
      // 섹션 `Rn3AC` 328×295 = 헤더 25 + 12 + 184 + 12 + 점 6 + 12 + 44.
      expect(bottom(replace) - y(find.text('실제 사진')), 295);

      // 기본 정보 `QldHz`: 32 → 헤더 25 → 12 → 카드 328×152(위아래 4 · 행 48 셋).
      expect(y(find.text('기본 정보')) - bottom(replace), 32);
      final facts = _shadowCard(of: find.text('내 키'));
      expect(y(facts) - bottom(find.text('기본 정보')), 12);
      expect(tester.getSize(facts), const Size(328, 152));
      final factRows = find.descendant(
        of: facts,
        matching: find.byWidgetPredicate((w) => w is ConstrainedBox && w.constraints.minHeight == 48),
      );
      expect(factRows, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        expect(y(factRows.at(i)), y(facts) + 4 + 48.0 * i);
        expect(tester.getSize(factRows.at(i)), const Size(296, 48));
      }

      // 선호 조건 `J0ZhR6`: 32 → 헤더 → 12 → 입구 행 328×84 → 12 → 328×84.
      expect(y(find.text('선호 조건')) - bottom(facts), 32);
      final age = find.widgetWithText(ProfileEntryRow, '선호 나이 범위');
      final height = find.widgetWithText(ProfileEntryRow, '선호 키 범위');
      expect(y(age) - bottom(find.text('선호 조건')), 12);
      expect(y(height) - bottom(age), 12);
      expect(tester.getSize(age), const Size(328, 84));
      expect(tester.getSize(height), const Size(328, 84));

      // 자기소개 `jVQAw`: 32 → 헤더 → 12 → 본문 → 12 → 15c 입구 행.
      expect(y(find.text('자기소개')) - bottom(height), 32);
      expect(y(find.text(_bio)) - bottom(find.text('자기소개')), 12);
      final entry = find.widgetWithText(ProfileEntryRow, '자기소개 · 태그');
      expect(y(entry) - bottom(find.text(_bio)), 12);
      expect(tester.getTopLeft(entry).dx, 16);
      expect(tester.getSize(entry).width, 328);
    });

    testWidgets('본문 아래 여백 40 — 끝까지 스크롤하면 15c 입구 행 끝과 화면 끝 사이가 40', (tester) async {
      usePenFrame(tester);
      await pump(tester);
      await scrollToEnd(tester);

      final entry = find.widgetWithText(ProfileEntryRow, '자기소개 · 태그');
      expect(780 - tester.getBottomLeft(entry).dy, 40);
    });
  });

  group('섹션 헤더 `Ymhdq`', () {
    testWidgets('제목 17/700 ink 렌더 25, 오른쪽 글자 14/400 muted 렌더 20 — space_between · 세로 가운데', (tester) async {
      usePenFrame(tester, height: 1600);
      await pump(tester);

      for (final title in ['실제 사진', '기본 정보', '선호 조건', '자기소개']) {
        final style = tester.widget<Text>(find.text(title)).style!;
        expect((style.fontSize, style.fontWeight, style.color), (17, FontWeight.w700, AppColors.ink), reason: title);
        expect(tester.getSize(find.text(title)).height, 25, reason: title);
      }
      for (final note in ['서로 수락하면 전달돼요', '수정 ›']) {
        final style = tester.widget<Text>(find.text(note)).style!;
        expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w400, AppColors.muted), reason: note);
        expect(tester.getSize(find.text(note)).height, 20, reason: note);
      }
      // 오른쪽 끝(344)에 붙고 제목과 세로 가운데가 같다.
      for (final (title, note) in [('실제 사진', '서로 수락하면 전달돼요'), ('기본 정보', '수정 ›')]) {
        expect(tester.getTopRight(find.text(note)).dx, 344, reason: note);
        expect(tester.getCenter(find.text(note)).dy, tester.getCenter(find.text(title)).dy, reason: note);
      }
    });

    testWidgets('선호 조건 · 자기소개 헤더는 오른쪽 글자가 없다', (tester) async {
      usePenFrame(tester, height: 1600);
      await pump(tester);

      for (final title in ['선호 조건', '자기소개']) {
        final row = find.ancestor(of: find.text(title), matching: find.byType(Row)).first;
        expect(find.descendant(of: row, matching: find.byType(Text)), findsOneWidget, reason: title);
      }
    });
  });

  group('실제 사진 `Rn3AC`', () {
    testWidgets('슬라이더에 사진이 순서대로 다 넘어간다, 252×184', (tester) async {
      await pump(tester);

      final slider = tester.widget<PhotoSlider>(find.byType(PhotoSlider));
      expect(slider.photos, const [NetworkImage('https://img.test/1.png'), NetworkImage('https://img.test/2.png')]);
      expect(slider.photoSize, const Size(252, 184));
    });

    testWidgets('첫 장 배지 `r6b8Vu` "수락 후 공개" + lock 12 — ink 알약, 11/600 렌더 18, 높이 28', (tester) async {
      await pump(tester);

      final slider = find.byType(PhotoSlider);
      expect(find.descendant(of: slider, matching: find.text('수락 후 공개')), findsOneWidget);
      final lock = tester.widget<Icon>(find.descendant(of: slider, matching: find.byIcon(AppIcons.lock)));
      expect((lock.size, lock.color), (12, AppColors.onInk));
      final style = tester.widget<Text>(find.text('수락 후 공개')).style!;
      expect((style.fontSize, style.fontWeight, style.color), (11, FontWeight.w600, AppColors.onInk));
      expect(style.fontSize! * style.height!, closeTo(18, 0.01));
      final badge = find.ancestor(
        of: find.text('수락 후 공개'),
        matching: find.byWidgetPredicate(
          (w) => w is DecoratedBox && (w.decoration as BoxDecoration?)?.color == AppColors.surfaceInk,
        ),
      );
      expect(tester.getSize(badge).height, 28);
    });

    testWidgets('교체 버튼 `E7Cv2` — 눌림 효과 · 채움은 버튼 크기 Material(COMMON §4-2), 328×44 surface-strong 모서리 8, 14/600 ink', (tester) async {
      usePenFrame(tester);
      await pump(tester);
      await tester.scrollUntilVisible(find.text('실제 사진 교체'), 200, scrollable: _list);

      final button = find.ancestor(of: find.text('실제 사진 교체'), matching: find.byType(InkWell));
      final painter = find.ancestor(of: button, matching: find.byType(Material)).first;
      expect(tester.getSize(painter), const Size(328, 44));
      expect(tester.getSize(button), const Size(328, 44));
      final material = tester.widget<Material>(painter);
      expect((material.color, material.borderRadius), (AppColors.surfaceStrong, BorderRadius.circular(8)));
      final style = tester.widget<Text>(find.text('실제 사진 교체')).style!;
      expect((style.fontSize, style.fontWeight, style.color, style.height), (14, FontWeight.w600, AppColors.ink, 1.5));
    });
  });

  group('기본 정보 `QldHz`', () {
    Future<void> showFacts(WidgetTester tester) =>
        tester.scrollUntilVisible(find.text('학과'), 200, scrollable: _list);

    testWidgets('카드 `N1dIuc` — #FFFFFF · 모서리 14 · 카드 그림자(fN0xc 와 같은 두 겹), 구분선 없음', (tester) async {
      await pump(tester);
      await showFacts(tester);

      final card = _shadowCard(of: find.text('내 키'));
      expect(card, findsOneWidget);
      final decoration = tester.widget<DecoratedBox>(card).decoration as BoxDecoration;
      expect(
        (decoration.color, decoration.borderRadius, decoration.boxShadow),
        (AppColors.canvas, BorderRadius.circular(14), AppElevation.card),
      );
      expect(find.descendant(of: card, matching: find.byType(Divider)), findsNothing);
    });

    testWidgets('내 키 · MBTI · 학과 3행 — 아이콘 19 muted, 라벨 14/400 muted, 값 14/600 ink', (tester) async {
      await pump(tester);
      await showFacts(tester);

      for (final (label, value) in [('내 키', '178cm'), ('MBTI', 'ENFP'), ('학과', '경영학과')]) {
        final labelStyle = tester.widget<Text>(find.text(label)).style!;
        expect((labelStyle.fontSize, labelStyle.fontWeight, labelStyle.color), (14, FontWeight.w400, AppColors.muted));
        final valueStyle = tester.widget<Text>(find.text(value)).style!;
        expect((valueStyle.fontSize, valueStyle.fontWeight, valueStyle.color), (14, FontWeight.w600, AppColors.ink));
      }
      for (final icon in [AppIcons.ruler, AppIcons.badge, AppIcons.graduationCap]) {
        final widget = tester.widget<Icon>(
          find.descendant(of: _shadowCard(of: find.text('내 키')), matching: find.byIcon(icon)),
        );
        expect((widget.size, widget.color), (19, AppColors.muted), reason: '$icon');
      }
    });

    testWidgets('MBTI 가 없으면 행은 남고 값은 "선택 안 함"(사용자 결정 2026-09-27)', (tester) async {
      await pump(tester, result: Success(_profile(mbti: null)));
      await showFacts(tester);

      expect(find.text('MBTI'), findsOneWidget);
      expect(find.text('선택 안 함'), findsOneWidget);
    });

    testWidgets('키·학과가 없으면 값은 "-"', (tester) async {
      await pump(tester, result: Success(_profile(heightCm: null, major: null)));
      await showFacts(tester);

      expect(find.text('-'), findsNWidgets(2));
    });

    testWidgets('"수정 ›" 누름 칸은 44 이상(N12)이고 글자를 품는다, 눌림 효과는 그 칸 크기 Material(COMMON §4-2)', (tester) async {
      usePenFrame(tester);
      await pump(tester);
      await tester.scrollUntilVisible(find.text('수정 ›'), 200, scrollable: _list);

      final size = tester.getSize(_editLink);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(tester.getRect(_editLink).contains(tester.getCenter(find.text('수정 ›'))), isTrue);
      expect(tester.getCenter(_editLink).dy, closeTo(tester.getCenter(find.text('수정 ›')).dy, 0.01));
      final painter = find.ancestor(of: _editLink, matching: find.byType(Material)).first;
      expect(tester.getSize(painter), size);
    });
  });

  // 계획서 2026-09-28-me-profile.md A15 — "교체" 는 PR 4 에서 15-7 로 연결됐다.
  testWidgets('"실제 사진 교체" 를 누르면 15-7 사진 수정(/me/photos)으로 간다 — "곧 열려요" 는 뜨지 않는다', (tester) async {
    await pump(tester);

    await tapVisible(tester, find.text('실제 사진 교체'));
    await tester.pumpAndSettle();

    expect(find.text('15-7 사진 수정 화면'), findsOneWidget);
    expect(find.text('곧 열려요'), findsNothing);
  });

  // 계획서 2026-09-28-me-profile.md A16 — "수정 ›" 은 PR 3-2 에서 15-6 으로 연결됐다. 저장하고 돌아오면 "저장했어요"(B4).
  group('"수정 ›" → 15-6 기본 정보 수정', () {
    /// "수정 ›" 로 15-6 을 열고 [button]("15-6 저장" · "15-6 뒤로")으로 돌아온다. 돌아온 첫 프레임에서 멈춘다.
    Future<void> returnFromBasicInfo(WidgetTester tester, String button) async {
      await tapVisible(tester, find.text('수정 ›'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(button));
      await tester.pump();
    }

    testWidgets('"수정 ›" 을 누르면 15-6(/me/basic-info)으로 간다 — "곧 열려요" 는 뜨지 않는다', (tester) async {
      await pump(tester);

      await tapVisible(tester, find.text('수정 ›'));
      await tester.pumpAndSettle();

      expect(find.text('15-6 기본 정보 수정 화면'), findsOneWidget);
      expect(find.text('곧 열려요'), findsNothing);
    });

    testWidgets('15-6 에서 저장하고 돌아오면 "저장했어요"(circle-check 16 흰색)가 뜨고 약 2초 뒤 사라진다', (tester) async {
      await pump(tester);

      await returnFromBasicInfo(tester, '15-6 저장');
      expect(find.text('저장했어요'), findsOneWidget);
      final icon = tester.widget<Icon>(find.descendant(of: find.byType(AppToast), matching: find.byType(Icon)));
      expect((icon.icon, icon.size, icon.color), (AppIcons.circleCheck, 16, AppColors.onInk));

      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.byType(ProfileManageScreen), findsOneWidget);
      expect(find.text('저장했어요'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('저장했어요'), findsNothing);
    });

    testWidgets('저장 없이 돌아오면 아무 안내도 없다', (tester) async {
      await pump(tester);

      await returnFromBasicInfo(tester, '15-6 뒤로');
      await tester.pumpAndSettle();

      expect(find.byType(ProfileManageScreen), findsOneWidget);
      expect(find.byType(AppToast), findsNothing);
    });

    testWidgets('안내는 화면 아래 12, 가로 가운데에 뜬다 — 하단 버튼 · 내비가 없는 화면', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      await returnFromBasicInfo(tester, '15-6 저장');
      await tester.pumpAndSettle();

      final toast = find.byType(AppToast);
      expect(780 - tester.getBottomLeft(toast).dy, 12);
      expect(tester.getCenter(toast).dx, 180);
    });

    testWidgets('애니메이션 줄이기가 켜져 있어도 바로 뜨고 움직임이 없다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pump(tester);

      await returnFromBasicInfo(tester, '15-6 저장');
      expect(find.text('저장했어요'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.ancestor(of: find.byType(AppToast), matching: find.byType(FadeTransition)), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('저장했어요'), findsNothing);
    });

    testWidgets('떠 있는 동안 화면을 떠나도 타이머가 남지 않는다', (tester) async {
      await pump(tester);
      await returnFromBasicInfo(tester, '15-6 저장');

      await tester.pumpWidget(const SizedBox());

      // 타이머가 남아 있으면 flutter_test 가 "A Timer is still pending" 으로 실패시킨다.
      expect(find.text('저장했어요'), findsNothing);
    });
  });

  group('선호 조건 `J0ZhR6` — ProfileEntryRow 두 개(`sR3If` · `t1Eok`)', () {
    Future<void> showRows(WidgetTester tester) =>
        tester.scrollUntilVisible(find.text('선호 키 범위'), 200, scrollable: _list);

    ProfileEntryRow rowOf(WidgetTester tester, String title) =>
        tester.widget<ProfileEntryRow>(find.widgetWithText(ProfileEntryRow, title));

    testWidgets('선호 나이 "22세–27세"(calendar), 선호 키 "165cm ~ 180cm"(ruler) — pen 형식 그대로, 셰브런', (tester) async {
      await pump(tester);
      await showRows(tester);

      final age = rowOf(tester, '선호 나이 범위');
      final height = rowOf(tester, '선호 키 범위');
      expect((age.icon, age.note), (AppIcons.calendar, '22세–27세'));
      expect((height.icon, height.note), (AppIcons.ruler, '165cm ~ 180cm'));
      for (final title in ['선호 나이 범위', '선호 키 범위']) {
        final row = find.widgetWithText(ProfileEntryRow, title);
        expect(find.descendant(of: row, matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
      }
    });

    // U1 — 셰브런은 값을 고치는 화면(06-1 편집)으로 잇는다. 두 행 모두 같은 화면이다(06-1 에 나이 · 키가 같이 있다).
    for (final title in ['선호 나이 범위', '선호 키 범위']) {
      testWidgets('"$title" 행을 누르면 06-1 편집(`/me/ideal-conditions`)으로 간다', (tester) async {
        await pump(tester);

        await tapVisible(tester, find.text(title));
        await tester.pumpAndSettle();

        expect(find.text('06-1 편집 화면'), findsOneWidget);
      });
    }

    testWidgets('눌림 효과는 스크롤 밖이 아니라 행 크기 Material 이 그린다(COMMON §4-2)', (tester) async {
      usePenFrame(tester);
      await pump(tester);
      await showRows(tester);

      for (final title in ['선호 나이 범위', '선호 키 범위']) {
        final row = find.widgetWithText(ProfileEntryRow, title);
        final ink = find.descendant(of: row, matching: find.byType(InkWell));
        final painter = find.ancestor(of: ink, matching: find.byType(Material)).first;
        expect(tester.getSize(painter), const Size(328, 84), reason: title);
        expect(tester.getSize(ink), const Size(328, 84), reason: title);
      }
    });

    Future<String> noteOf(WidgetTester tester, String title, MyProfile profile) async {
      await pump(tester, result: Success(profile));
      await showRows(tester);
      return rowOf(tester, title).note;
    }

    for (final (title, profile, note) in [
      ('선호 키 범위', _profile(preferredHeightMin: null, preferredHeightMax: null), '상관없어요'),
      ('선호 키 범위', _profile(preferredHeightMax: null), '상관없어요'),
      ('선호 나이 범위', _profile(preferredAgeMin: null, preferredAgeMax: null), '상관없어요'),
      // 나이가 전 구간(19~35)이면 06-1 "나이는 상관없어요" 와 같다.
      ('선호 나이 범위', _profile(preferredAgeMin: 19, preferredAgeMax: 35), '상관없어요'),
      // 나이 아래 끝 19 는 06-1 처럼 그대로 "19세".
      ('선호 나이 범위', _profile(preferredAgeMin: 19, preferredAgeMax: 27), '19세–27세'),
      // 끝값 표기는 06-1(`ideal_conditions_screen` _ageSummary·_heightSummary)과 같다 — 사용자 결정 2026-09-27.
      ('선호 나이 범위', _profile(preferredAgeMin: 25, preferredAgeMax: 35), '25세–35세 이상'),
      ('선호 키 범위', _profile(preferredHeightMin: 150, preferredHeightMax: 180), '150cm 이하 ~ 180cm'),
      ('선호 키 범위', _profile(preferredHeightMin: 165, preferredHeightMax: 190), '165cm ~ 190cm 이상'),
      ('선호 키 범위', _profile(preferredHeightMin: 150, preferredHeightMax: 190), '150cm 이하 ~ 190cm 이상'),
    ]) {
      testWidgets('"$title" 표기 — "$note"', (tester) async {
        expect(await noteOf(tester, title, profile), note);
      });
    }
  });

  group('자기소개 `jVQAw`', () {
    final entry = find.widgetWithText(ProfileEntryRow, '자기소개 · 태그');

    testWidgets('본문 `IUPXc` 16/400 body 줄높이 1.6', (tester) async {
      await pump(tester);
      await scrollToEnd(tester);

      final style = tester.widget<Text>(find.text(_bio)).style!;
      expect((style.fontSize, style.fontWeight, style.color, style.height), (16, FontWeight.w400, AppColors.body, 1.6));
    });

    for (final bio in [null, '', '  ']) {
      testWidgets('자기소개가 비면("$bio") 본문만 숨기고 헤더 · 15c 입구 행(헤더 아래 12)은 남는다', (tester) async {
        await pump(tester, result: Success(_profile(bio: bio)));
        await scrollToEnd(tester);

        expect(find.text('자기소개'), findsOneWidget);
        expect(tester.getTopLeft(entry).dy - tester.getBottomLeft(find.text('자기소개')).dy, 12);
      });
    }

    testWidgets('15c 입구 행 `bTDTS` — tags(pen Lucide 이름 그대로), "자기소개 · 태그" / "관심사 · 나의 특징 · 이상형", 셰브런', (tester) async {
      await pump(tester);
      await scrollToEnd(tester);

      final row = tester.widget<ProfileEntryRow>(entry);
      expect((row.icon, row.title, row.note), (AppIcons.tags, '자기소개 · 태그', '관심사 · 나의 특징 · 이상형'));
      expect(AppIcons.tags, LucideIcons.tags);
      expect(find.descendant(of: entry, matching: find.byIcon(AppIcons.chevronRight)), findsOneWidget);
    });

    testWidgets('누르면 15c 자기소개·태그 수정(`/me/edit`)으로 간다', (tester) async {
      await pump(tester);
      await scrollToEnd(tester);

      await tester.tap(entry);
      await tester.pumpAndSettle();

      expect(find.text('15c 편집 화면'), findsOneWidget);
    });

    testWidgets('눌림 효과는 스크롤 밖이 아니라 행 크기 Material 이 그린다(COMMON §4-2)', (tester) async {
      usePenFrame(tester);
      await pump(tester);
      await scrollToEnd(tester);

      final ink = find.descendant(of: entry, matching: find.byType(InkWell));
      final painter = find.ancestor(of: ink, matching: find.byType(Material)).first;
      expect(tester.getSize(painter), tester.getSize(entry));
      expect(tester.getSize(ink), tester.getSize(entry));
    });
  });

  testWidgets('15-5 아이콘은 pen 의 Lucide 이름과 같다(`sR3If` calendar · `t1Eok` ruler · `N1dIuc` badge · lock)', (tester) async {
    expect(AppIcons.calendar, LucideIcons.calendar);
    expect(AppIcons.ruler, LucideIcons.ruler);
    expect(AppIcons.badge, LucideIcons.badge);
    expect(AppIcons.lock, LucideIcons.lock);
  });

  group('불러오는 중 · 실패(N9 — pen 에 없는 상태, 화면 15 와 같은 모양)', () {
    testWidgets('불러오는 중이면 가운데 로딩 표시, 앱바는 그대로', (tester) async {
      await pump(tester, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(EditAppBar), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('실패하면 MeLoadError(문구 + "다시 시도"), 앱바는 그대로', (tester) async {
      await pump(tester, result: const FailureResult(NetworkFailure()));

      expect(find.byType(MeLoadError), findsOneWidget);
      expect(find.text('잠시 뒤 다시 시도해 주세요'), findsOneWidget);
      expect(find.byType(EditAppBar), findsOneWidget);
    });

    testWidgets('"다시 시도" 를 누르면 다시 불러와 화면을 그린다', (tester) async {
      final repository = await pump(tester, result: const FailureResult(NetworkFailure()));
      expect(repository.calls, 1);

      repository.profile = Success(_profile());
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();

      expect(repository.calls, 2);
      expect(find.text('실제 사진'), findsOneWidget);
    });
  });

  // Review Focus 2 — 15c 는 저장 뒤 invalidate 하고 pop 한다. 15-5 에서 열면 15 가 아니라 15-5 로 돌아와 새 값을 그린다(N8).
  testWidgets('saving_in_15c_returns_to_15_5_with_the_new_bio — 가짜 저장소 + 실제 라우터', (tester) async {
    final me = FakeMeRepository(Success(_profile()));
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: () => VerificationGate.complete,
      onboardingStep: () => OnboardingStep.complete,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 첫 화면(홈)이 하단 내비 뱃지와 요약을 읽는다.
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          meRepositoryProvider.overrideWithValue(me),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    router.go(AppRoutes.myProfileManage);
    await tester.pumpAndSettle();
    await scrollToEnd(tester);
    await tester.tap(find.widgetWithText(ProfileEntryRow, '자기소개 · 태그'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileEditScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), '새 소개예요.');
    await tester.pump();
    // 서버는 PATCH 를 받는 동안 값을 바꾼다 — 15-5 가 다시 읽어야만 새 글이 보인다.
    me.holdUpdate = Completer<void>();
    await tester.tap(find.widgetWithText(AppButton, '저장'));
    await tester.pump();
    me.profile = Success(_profile(bio: '새 소개예요.'));
    me.holdUpdate!.complete();
    await tester.pumpAndSettle();

    expect(me.updates, [
      {'bio': '새 소개예요.'},
    ]);
    expect(find.byType(ProfileEditScreen), findsNothing);
    expect(find.byType(ProfileManageScreen), findsOneWidget);
    await scrollToEnd(tester);
    expect(find.text('새 소개예요.'), findsOneWidget);
    expect(find.text(_bio), findsNothing);
  });

  // N8 — 15-7 도 저장 뒤 invalidate 하고 pop 한다. 15-5 로 돌아와 실제 사진 줄이 새 값을 그린다.
  testWidgets('saving_in_15_7_returns_to_15_5_with_the_new_photos — 가짜 저장소 + 실제 라우터', (tester) async {
    const urls = ['https://img.test/1.png', 'https://img.test/2.png', 'https://img.test/3.png'];
    final me = FakeMeRepository(Success(_profile(photoUrls: urls)));
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: () => VerificationGate.complete,
      onboardingStep: () => OnboardingStep.complete,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 첫 화면(홈)이 하단 내비 뱃지와 요약을 읽는다.
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          meRepositoryProvider.overrideWithValue(me),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    router.go(AppRoutes.myProfileManage);
    await tester.pumpAndSettle();
    expect(tester.widget<PhotoSlider>(find.byType(PhotoSlider)).photos, hasLength(3));
    await tapVisible(tester, find.text('실제 사진 교체'));
    await tester.pumpAndSettle();
    expect(find.byType(MyPhotosScreen), findsOneWidget);

    // 셋째 사진을 빼고 저장한다. 서버는 PUT 을 받는 동안 값을 바꾼다 — 15-5 가 다시 읽어야만 새 사진 줄이 보인다.
    await tester.tap(find.byIcon(AppIcons.x).at(2));
    await tester.pump();
    me.holdSavePhotos = Completer<void>();
    await tester.tap(find.widgetWithText(AppButton, '저장'));
    await tester.pump();
    me.profile = Success(_profile(photoUrls: urls.take(2).toList()));
    me.holdSavePhotos!.complete();
    await tester.pumpAndSettle();

    final (slots, avatarSource) = me.photoSaves.single;
    expect(slots, const [KeptPhoto('p-0'), KeptPhoto('p-1')]);
    expect(avatarSource, 0);
    expect(find.byType(MyPhotosScreen), findsNothing);
    expect(find.byType(ProfileManageScreen), findsOneWidget);
    expect(
      tester.widget<PhotoSlider>(find.byType(PhotoSlider)).photos,
      const [NetworkImage('https://img.test/1.png'), NetworkImage('https://img.test/2.png')],
    );
  });

  // N8 + B4 — 15-6 은 저장 뒤 invalidate 하고 true 를 돌려주며 pop 한다. 15-5 로 돌아와 새 키를 그리고 "저장했어요" 를 띄운다.
  testWidgets('saving_in_15_6_returns_to_15_5_with_the_new_height_and_a_toast — 가짜 저장소 + 실제 라우터', (tester) async {
    final me = FakeMeRepository(Success(_profile()));
    final router = AppRouter.create(
      isAuthenticated: () => true,
      verificationGate: () => VerificationGate.complete,
      onboardingStep: () => OnboardingStep.complete,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 첫 화면(홈)이 하단 내비 뱃지와 요약을 읽는다.
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          homeRepositoryProvider.overrideWithValue(FakeHomeRepository(const FailureResult(NetworkFailure()))),
          meRepositoryProvider.overrideWithValue(me),
        ],
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    router.go(AppRoutes.myProfileManage);
    await tester.pumpAndSettle();
    expect(find.text('178cm'), findsOneWidget);
    await tapVisible(tester, find.text('수정 ›'));
    await tester.pumpAndSettle();
    expect(find.byType(BasicInfoEditScreen), findsOneWidget);

    // 키만 고쳐 저장한다. 서버는 PATCH 를 받는 동안 값을 바꾼다 — 15-5 가 다시 읽어야만 새 키가 보인다.
    await tester.enterText(find.byType(TextField).at(1), '181');
    await tester.pump();
    me.holdUpdate = Completer<void>();
    await tester.tap(find.widgetWithText(AppButton, '저장'));
    await tester.pump();
    me.profile = Success(_profile(heightCm: 181));
    me.holdUpdate!.complete();
    await tester.pumpAndSettle();

    expect(me.updates, [
      {'height_cm': 181},
    ]);
    expect(find.byType(BasicInfoEditScreen), findsNothing);
    expect(find.byType(ProfileManageScreen), findsOneWidget);
    expect(find.text('저장했어요'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('181cm'), 200, scrollable: _list);
    expect(find.text('181cm'), findsOneWidget);
    expect(find.text('178cm'), findsNothing);
    await tester.pump(const Duration(seconds: 2)); // 토스트 타이머를 끝내 둔다
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 깨지지 않는다. 화면 15 테스트와 같은 잣대.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('15-5 — 폭 360 · 글자 배율 $scale 에서 넘침 · 잘림이 없다(스크롤 전 · 끝), "수정 ›" 누름 칸은 글자를 품는다', (tester) async {
      // 테스트 글꼴은 한글이 Pretendard 보다 넓다 — 여기서 버티면 실제 폰에서도 버틴다.
      usePenFrame(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(tester);
      expect(tester.takeException(), isNull);
      final clipped = _clippedTexts();
      await tester.scrollUntilVisible(find.text('수정 ›'), 200, scrollable: _list);
      expect(tester.getRect(_editLink).contains(tester.getCenter(find.text('수정 ›'))), isTrue);
      clipped.addAll(_clippedTexts());
      await scrollToEnd(tester);
      clipped.addAll(_clippedTexts());

      expect(tester.takeException(), isNull);
      expect(clipped, isEmpty);
    });
  }
}

/// 고정 상자에 갇혀 오류 없이 잘린 글자. 폭은 배치 때 받은 최대 폭으로 잰다(화면 15 테스트와 같은 방식).
List<String> _clippedTexts() => [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.getMaxIntrinsicHeight(p.constraints.maxWidth) > p.size.height + 0.5 ||
                p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
          p.text.toPlainText(),
    ];
