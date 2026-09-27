import 'dart:async';
import 'dart:io';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/photo_slider.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/my_profile_screen.dart';
import 'package:campus_mate/me/view/profile_entry_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mocktail/mocktail.dart';

import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../model/fake_me_repository.dart';

/// 사진 요청을 받기만 하고 답하지 않는 HttpClient. 테스트의 기본 HttpClient 는 400 을 돌려줘
/// NetworkImage 가 오류를 내므로, 그림은 "아직 오는 중" 으로 둔다(크기·자리는 그림과 상관없다).
class _PendingHttpClient extends Mock implements HttpClient {}

/// NetworkImage 는 처음 쓸 때 만든 HttpClient 하나를 계속 쓴다 — 그 전에 이 파일 전체에 건다.
/// (`debugNetworkImageHttpClientProvider` 는 테스트마다 tearDown 보다 먼저 "바뀐 채 끝남" 검사에 걸린다.)
class _PendingHttpOverrides extends HttpOverrides {
  _PendingHttpOverrides(this._client);

  final HttpClient _client;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _client;
}

const _bio = '주말엔 카페 투어와 등산을 즐겨요. 새로운 사람을 만나는 걸 좋아하고, 대화가 잘 통하는 사람을 찾고 있어요.';

/// 이름·학교는 지어낸 값이다.
MyProfile _profile({
  int? age = 23,
  String? major = '경영학과',
  int? heightCm = 178,
  String? mbti = 'ENFP',
  String? avatarUrl = 'https://img.test/avatar.png',
  List<String> photoUrls = const ['https://img.test/1.png', 'https://img.test/2.png'],
  int? preferredAgeMin = 22,
  int? preferredAgeMax = 27,
  int? preferredHeightMin = 165,
  int? preferredHeightMax = 180,
  String? bio = _bio,
}) =>
    MyProfile(
      nickname: '여우',
      age: age,
      university: '가나대학교',
      major: major,
      heightCm: heightCm,
      mbti: mbti,
      avatarUrl: avatarUrl,
      photoUrls: photoUrls,
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

Finder _fill(Color color, {required Finder of}) => find.ancestor(
      of: of,
      matching: find.byWidgetPredicate(
        (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == color,
      ),
    );

void main() {
  final previousOverrides = HttpOverrides.current;
  setUpAll(() {
    registerFallbackValue(Uri());
    final client = _PendingHttpClient();
    when(() => client.getUrl(any())).thenAnswer((_) => Completer<HttpClientRequest>().future);
    HttpOverrides.global = _PendingHttpOverrides(client);
  });
  tearDownAll(() => HttpOverrides.global = previousOverrides);

  /// [settle] 이 false 면 첫 프레임(불러오는 중)에서 멈춘다.
  Future<FakeMeRepository> pump(
    WidgetTester tester, {
    Result<MyProfile>? result,
    bool settle = true,
  }) async {
    final repository = FakeMeRepository(result ?? Success(_profile()));
    final container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(repository),
        // 하단 내비 뱃지가 수락 대기·안 읽은 메시지를 읽는다(§8.8).
        cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.myProfile,
      routes: [
        GoRoute(path: AppRoutes.myProfile, builder: (context, state) => const MyProfileScreen()),
        GoRoute(path: AppRoutes.settings, builder: (context, state) => const Scaffold(body: Text('설정 화면'))),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    if (settle) await tester.pump();
    return repository;
  }

  void usePenFrame(WidgetTester tester, {double height = 884}) {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// ListView 는 아래 칸을 그리기 전엔 끝 길이를 어림한다 — 한 번 끌면 어림한 끝에서 멈추므로 진짜 끝까지 되풀이한다.
  Future<void> scrollToEnd(WidgetTester tester) async {
    final position = tester.state<ScrollableState>(_list).position;
    do {
      await tester.drag(_list, const Offset(0, -3000));
      await tester.pumpAndSettle();
    } while (position.pixels < position.maxScrollExtent);
  }

  group('앱바 `ffOFL`', () {
    testWidgets('제목 "내 프로필" 과 설정 톱니(48×48, settings 22 ink)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(find.text('내 프로필'), findsOneWidget);
      final gear = find.byTooltip('설정');
      expect(tester.getSize(gear), const Size(48, 48));
      // pen `C7teyl` x304 y4 — 오른쪽 여백 8.
      expect(tester.getTopLeft(gear), const Offset(304, 4));
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.settings));
      expect((icon.size, icon.color), (22, AppColors.ink));
    });

    testWidgets('톱니를 누르면 설정으로 간다', (tester) async {
      // pen 에서 설정(16)으로 가는 문은 15 내 프로필 `r8oJc` 의 톱니(`ffOFL` 안 `C7teyl`) 하나뿐이다.
      await pump(tester);

      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();

      expect(find.text('설정 화면'), findsOneWidget);
    });
  });

  testWidgets('하단 내비는 "나" 탭이 켜져 있다', (tester) async {
    await pump(tester);

    expect(tester.widget<AppBottomNav>(find.byType(AppBottomNav)).current, AppTab.me);
  });

  group('헤더 `mHdp8`', () {
    testWidgets('"닉네임, 나이" 와 "학교 · 학과", 학생 인증 배지', (tester) async {
      await pump(tester);

      expect(find.text('여우, 23'), findsOneWidget);
      expect(find.text('가나대학교 · 경영학과'), findsOneWidget);
      expect(find.text('학생 인증'), findsOneWidget);
      expect(find.byIcon(AppIcons.badgeCheck), findsOneWidget);
    });

    testWidgets('나이·학과가 없으면 그 부분만 뺀다', (tester) async {
      await pump(tester, result: Success(_profile(age: null, major: null)));

      expect(find.text('여우'), findsOneWidget);
      expect(find.text('가나대학교'), findsOneWidget);
      // 배지는 늘 보인다 — 이 API 는 인증된 사람만 닿는다.
      expect(find.text('학생 인증'), findsOneWidget);
    });
  });

  group('아바타 섹션 `p3iPK`', () {
    testWidgets('제목과 아바타 그림, "AI 아바타" 배지(sparkles)', (tester) async {
      await pump(tester);

      expect(find.text('상대에게는 이렇게 보여요'), findsOneWidget);
      expect(_imageBox('https://img.test/avatar.png'), findsOneWidget);
      expect(find.text('AI 아바타'), findsOneWidget);
      expect(find.byIcon(AppIcons.sparkles), findsOneWidget);
    });

    testWidgets('아바타가 없으면 같은 크기의 빈 칸(surface-soft)이다', (tester) async {
      usePenFrame(tester);
      await pump(tester, result: Success(_profile(avatarUrl: null)));

      final box = _fill(AppColors.surfaceSoft, of: find.text('AI 아바타')).first;
      expect(tester.getSize(box), const Size(328, 198));
      expect((tester.widget<DecoratedBox>(box).decoration as BoxDecoration).image, isNull);
    });
  });

  group('실사진 섹션 `fwReS`', () {
    testWidgets('제목은 "서로 수락하면 전달돼요", 슬라이더에 사진이 순서대로 다 넘어간다', (tester) async {
      await pump(tester);

      expect(find.text('서로 수락하면 전달돼요'), findsOneWidget);
      final slider = tester.widget<PhotoSlider>(find.byType(PhotoSlider));
      expect(slider.photos, const [NetworkImage('https://img.test/1.png'), NetworkImage('https://img.test/2.png')]);
      expect(slider.photoSize, const Size(252, 184));
    });

    testWidgets('첫 장 배지는 "수락 후 공개" + lock', (tester) async {
      await pump(tester);

      final slider = find.byType(PhotoSlider);
      expect(find.descendant(of: slider, matching: find.text('수락 후 공개')), findsOneWidget);
      expect(find.descendant(of: slider, matching: find.byIcon(AppIcons.lock)), findsOneWidget);
    });
  });

  group('"실제 사진 교체" `M1OptH`', () {
    Future<void> tapReplace(WidgetTester tester) async {
      // scrollUntilVisible 은 "만들어졌다" 까지만 본다 — 화면 밖(캐시 영역)이면 눌리지 않아 화면 안으로 끌어온다.
      await tester.scrollUntilVisible(find.text('실제 사진 교체'), 200, scrollable: _list);
      await tester.ensureVisible(find.text('실제 사진 교체'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('실제 사진 교체'));
      await tester.pump();
    }

    testWidgets('누르면 "곧 열려요" 가 뜨고 약 2초 뒤 사라진다(사용자 결정 2026-09-27)', (tester) async {
      await pump(tester);

      await tapReplace(tester);
      expect(find.text('곧 열려요'), findsOneWidget);
      expect(find.byIcon(AppIcons.clock3), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.text('곧 열려요'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('곧 열려요'), findsNothing);
    });

    testWidgets('안내는 하단 내비 바로 위 12, 가로 가운데에 뜬다(DESIGN 토스트 공통 규칙)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      await tapReplace(tester);

      final toast = find.byType(AppToast);
      expect(tester.getTopLeft(find.byType(AppBottomNav)).dy - tester.getBottomLeft(toast).dy, 12);
      expect(tester.getCenter(toast).dx, 180);
    });

    testWidgets('애니메이션 줄이기가 켜져 있어도 바로 뜨고 2초 뒤 사라진다 — 움직임이 없다', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pump(tester);

      await tapReplace(tester);
      expect(find.text('곧 열려요'), findsOneWidget);
      expect(find.ancestor(of: find.byType(AppToast), matching: find.byType(FadeTransition)), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('곧 열려요'), findsNothing);
    });

    testWidgets('떠 있는 동안 화면을 떠나도 타이머가 남지 않는다', (tester) async {
      await pump(tester);
      await tapReplace(tester);

      await tester.pumpWidget(const SizedBox());

      // 타이머가 남아 있으면 flutter_test 가 "A Timer is still pending" 으로 실패시킨다.
      expect(find.text('곧 열려요'), findsNothing);
    });

    testWidgets('눌림 효과·채움은 스크롤 밖이 아니라 버튼 크기 Material 이 그린다(COMMON §4-2) — pen 328×44, surface-strong, 모서리 8, 14/600 ink', (tester) async {
      usePenFrame(tester);
      await pump(tester);
      await tester.scrollUntilVisible(find.text('실제 사진 교체'), 200, scrollable: _list);

      final button = find.ancestor(of: find.text('실제 사진 교체'), matching: find.byType(InkWell));
      final painter = find.ancestor(of: button, matching: find.byType(Material)).first;
      // 가장 가까운 Material 이 화면 전체면 스크롤 뒤 눌림 효과가 공중에 뜬다.
      expect(tester.getSize(painter), const Size(328, 44));
      expect(tester.getSize(button), const Size(328, 44));
      final material = tester.widget<Material>(painter);
      expect(material.color, AppColors.surfaceStrong);
      expect(material.borderRadius, BorderRadius.circular(8));
      final style = tester.widget<Text>(find.text('실제 사진 교체')).style!;
      expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, AppColors.ink));
    });
  });

  group('Profile Facts `FxO58`', () {
    testWidgets('내 키 · MBTI · 학과 3행', (tester) async {
      await pump(tester);
      await tester.scrollUntilVisible(find.text('학과'), 200, scrollable: _list);

      for (final (label, value) in [('내 키', '178cm'), ('MBTI', 'ENFP'), ('학과', '경영학과')]) {
        expect(find.text(label), findsOneWidget, reason: label);
        expect(find.text(value), findsOneWidget, reason: value);
      }
      expect(find.byIcon(AppIcons.badge), findsOneWidget);
      expect(find.byIcon(AppIcons.graduationCap), findsOneWidget);
    });

    testWidgets('MBTI 가 없으면 행은 남고 값은 "선택 안 함"(사용자 결정 2026-09-27)', (tester) async {
      await pump(tester, result: Success(_profile(mbti: null)));
      await tester.scrollUntilVisible(find.text('학과'), 200, scrollable: _list);

      expect(find.text('MBTI'), findsOneWidget);
      expect(find.text('선택 안 함'), findsOneWidget);
    });

    testWidgets('키·학과가 없으면 값은 "-"', (tester) async {
      await pump(tester, result: Success(_profile(heightCm: null, major: null)));
      await tester.scrollUntilVisible(find.text('학과'), 200, scrollable: _list);

      expect(find.text('-'), findsNWidgets(2));
    });
  });

  group('ProfileEntryRow 두 개', () {
    Future<void> showRows(WidgetTester tester) =>
        tester.scrollUntilVisible(find.text('선호 키 범위'), 200, scrollable: _list);

    testWidgets('선호 나이 "22세–27세"(calendar), 선호 키 "165cm ~ 180cm"(ruler) — pen 형식 그대로', (tester) async {
      await pump(tester);
      await showRows(tester);

      final rows = find.byType(ProfileEntryRow);
      expect(rows, findsNWidgets(2));
      final age = tester.widget<ProfileEntryRow>(rows.at(0));
      final height = tester.widget<ProfileEntryRow>(rows.at(1));
      expect((age.icon, age.title, age.note), (AppIcons.calendar, '선호 나이 범위', '22세–27세'));
      expect((height.icon, height.title, height.note), (AppIcons.ruler, '선호 키 범위', '165cm ~ 180cm'));
      expect(find.descendant(of: rows, matching: find.byIcon(AppIcons.chevronRight)), findsNWidgets(2));
      expect(find.descendant(of: rows, matching: find.byType(InkWell)), findsNothing);
    });

    Future<String> noteOf(WidgetTester tester, int index, MyProfile profile) async {
      await pump(tester, result: Success(profile));
      await showRows(tester);
      return tester.widget<ProfileEntryRow>(find.byType(ProfileEntryRow).at(index)).note;
    }

    testWidgets('키 범위가 없으면 "상관없어요"', (tester) async {
      await pump(tester, result: Success(_profile(preferredHeightMin: null, preferredHeightMax: null)));
      await showRows(tester);

      expect(tester.widget<ProfileEntryRow>(find.byType(ProfileEntryRow).at(1)).note, '상관없어요');
    });

    testWidgets('키 범위가 한쪽만 비어도 "상관없어요"', (tester) async {
      expect(await noteOf(tester, 1, _profile(preferredHeightMax: null)), '상관없어요');
    });

    // 끝값 표기는 06-1(`ideal_conditions_screen` _ageSummary·_heightSummary)과 같다 — 사용자 결정 2026-09-27.
    for (final (index, profile, note) in [
      (0, _profile(preferredAgeMin: 25, preferredAgeMax: 35), '25세–35세 이상'),
      (1, _profile(preferredHeightMin: 150, preferredHeightMax: 180), '150cm 이하 ~ 180cm'),
      (1, _profile(preferredHeightMin: 165, preferredHeightMax: 190), '165cm ~ 190cm 이상'),
      (1, _profile(preferredHeightMin: 150, preferredHeightMax: 190), '150cm 이하 ~ 190cm 이상'),
    ]) {
      testWidgets('끝값이면 06-1 처럼 "이상/이하" 를 붙인다 — "$note"', (tester) async {
        expect(await noteOf(tester, index, profile), note);
      });
    }

    testWidgets('나이 아래 끝 19 는 06-1 처럼 그대로 "19세"', (tester) async {
      expect(await noteOf(tester, 0, _profile(preferredAgeMin: 19, preferredAgeMax: 27)), '19세–27세');
    });

    testWidgets('나이가 전 구간(19~35)이면 "상관없어요"', (tester) async {
      await pump(tester, result: Success(_profile(preferredAgeMin: 19, preferredAgeMax: 35)));
      await showRows(tester);

      expect(tester.widget<ProfileEntryRow>(find.byType(ProfileEntryRow).at(0)).note, '상관없어요');
    });

    testWidgets('나이 범위가 없어도 "상관없어요"', (tester) async {
      await pump(tester, result: Success(_profile(preferredAgeMin: null, preferredAgeMax: null)));
      await showRows(tester);

      expect(tester.widget<ProfileEntryRow>(find.byType(ProfileEntryRow).at(0)).note, '상관없어요');
    });
  });

  group('자기소개 `pP9uk`', () {
    testWidgets('제목과 본문이 있다', (tester) async {
      await pump(tester);
      await scrollToEnd(tester);

      expect(find.text('자기소개'), findsOneWidget);
      expect(find.text(_bio), findsOneWidget);
    });

    for (final bio in [null, '', '  ']) {
      testWidgets('자기소개가 비면("$bio") 섹션을 통째로 숨긴다', (tester) async {
        await pump(tester, result: Success(_profile(bio: bio)));
        await scrollToEnd(tester);

        expect(find.text('자기소개'), findsNothing);
      });
    }
  });

  testWidgets('pen 에서 뺀 세 개(아바타 다시 만들기·친구들이 본 나·프로필 수정)는 없다', (tester) async {
    await pump(tester);

    for (final pass in ['처음', '끝까지 스크롤한 뒤']) {
      expect(find.textContaining('아바타 다시 만들기'), findsNothing, reason: pass);
      expect(find.text('친구들이 본 나'), findsNothing, reason: pass);
      expect(find.text('프로필 수정'), findsNothing, reason: pass);
      await scrollToEnd(tester);
    }
  });

  group('불러오는 중·실패(사용자 결정 2026-09-27, school_info 와 같은 모양)', () {
    testWidgets('불러오는 중이면 가운데 로딩 표시, 앱바 톱니와 하단 내비는 그대로', (tester) async {
      await pump(tester, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('설정'), findsOneWidget);
      expect(find.byType(AppBottomNav), findsOneWidget);
      await tester.pump();
    });

    testWidgets('실패하면 문구와 "다시 시도", 앱바 톱니와 하단 내비는 그대로', (tester) async {
      await pump(tester, result: const FailureResult(NetworkFailure()));

      // 사용자 결정 2026-09-27 — 공통 "알 수 없는 오류" 문구가 아니다.
      expect(find.text('잠시 뒤 다시 시도해 주세요'), findsOneWidget);
      expect(find.text(const UnknownFailure().toDisplayMessage()), findsNothing);
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.byTooltip('설정'), findsOneWidget);
      expect(find.byType(AppBottomNav), findsOneWidget);
    });

    testWidgets('"다시 시도" 를 누르면 다시 불러와 화면을 그린다', (tester) async {
      final repository = await pump(tester, result: const FailureResult(NetworkFailure()));
      expect(repository.calls, 1);

      repository.profile = Success(_profile());
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      await tester.pump();

      expect(repository.calls, 2);
      expect(find.text('여우, 23'), findsOneWidget);
    });
  });

  testWidgets('화면 15 새 아이콘은 pen 의 Lucide 이름과 같다(`CRZX0` · `K31sZl` · `vFPb8` · `Wb0JO`)', (tester) async {
    expect(AppIcons.sparkles, LucideIcons.sparkles);
    expect(AppIcons.ruler, LucideIcons.ruler);
    expect(AppIcons.calendar, LucideIcons.calendar);
    expect(AppIcons.badge, LucideIcons.badge);
  });

  group('pen 좌표(배율 1.0, 본문 = 앱바 아래)', () {
    testWidgets('섹션 사이 24 · 아바타↔실사진 16 · 제목↔내용 8, 주요 크기', (tester) async {
      // 전부 한 화면에 들어오게 세로만 늘린다. 값은 값표 1절 "숨길 요소를 뺀 뒤" 계산값.
      usePenFrame(tester, height: 1500);
      await pump(tester);

      final top = tester.getBottomLeft(find.byType(AppBar)).dy;
      expect(top, 56);
      double y(Finder finder) => tester.getTopLeft(finder).dy - top;

      // 헤더 0~62: 닉네임 37(`xew8J` 렌더) + 3 + 학교 줄 22(`q9by2M` 렌더).
      expect(y(find.text('여우, 23')), 0);
      expect(tester.getSize(find.text('여우, 23')).height, 37);
      expect(y(find.text('가나대학교 · 경영학과')), 40);
      expect(tester.getSize(find.text('가나대학교 · 경영학과')).height, 22);
      final badge = _fill(AppColors.surfaceInk, of: find.text('학생 인증')).first;
      expect(y(badge), 0);
      expect(tester.getSize(badge).height, 30);
      expect(tester.getTopRight(badge).dx, 344);

      // 아바타 섹션 86: 제목 22(`rxNdD` 렌더) + 8 + 아바타 328×198.
      expect(y(find.text('상대에게는 이렇게 보여요')), 86);
      expect(tester.getSize(find.text('상대에게는 이렇게 보여요')).height, 22);
      final avatar = _imageBox('https://img.test/avatar.png');
      expect(y(avatar), 116);
      expect(tester.getSize(avatar), const Size(328, 198));
      final aiBadge = _fill(AppColors.surfaceInk, of: find.text('AI 아바타')).first;
      // `CRZX0` 위 14, 오른쪽 13, 높이 28.
      expect(y(aiBadge), 130);
      expect(tester.getTopRight(aiBadge).dx, 344 - 13);
      expect(tester.getSize(aiBadge).height, 28);

      // 실사진 섹션 330(= 116 + 198 + 16): 제목 22 + 8 + 사진 184 + 8 + 점 6 + 8 + 버튼 44.
      expect(y(find.text('서로 수락하면 전달돼요')), 330);
      expect(y(_imageBox('https://img.test/1.png')), 360);
      final replace = find.ancestor(of: find.text('실제 사진 교체'), matching: find.byType(InkWell));
      expect(y(replace), 566);

      // Facts 634(= 610 + 24): 328×152, 행 48 셋(위아래 패딩 4).
      final facts = _fill(AppColors.surfaceSoft, of: find.text('내 키')).first;
      expect(y(facts), 634);
      expect(tester.getSize(facts), const Size(328, 152));
      final factRows = find.descendant(
        of: facts,
        matching: find.byWidgetPredicate((w) => w is ConstrainedBox && w.constraints.minHeight == 48),
      );
      expect(factRows, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        expect(y(factRows.at(i)), 638 + 48.0 * i);
        expect(tester.getSize(factRows.at(i)), const Size(296, 48));
      }

      // EntryRow 810 · 918, 328×84.
      final rows = find.byType(ProfileEntryRow);
      expect(y(rows.at(0)), 810);
      expect(y(rows.at(1)), 918);
      expect(tester.getSize(rows.at(0)), const Size(328, 84));

      // 자기소개 1026: 제목 21(`ISElO` 렌더) + 8 + 본문.
      expect(y(find.text('자기소개')), 1026);
      expect(y(find.text(_bio)), 1055);
    });

    testWidgets('본문 아래 여백 32 — 끝까지 스크롤하면 자기소개 끝과 내비 사이가 32', (tester) async {
      usePenFrame(tester);
      await pump(tester);
      await scrollToEnd(tester);

      expect(tester.getTopLeft(find.byType(AppBottomNav)).dy - tester.getBottomLeft(find.text(_bio)).dy, 32);
      expect(tester.getTopLeft(find.text(_bio)).dx, 16);
    });

    testWidgets('글자 스타일은 pen 값과 같다(줄높이는 1.5, 렌더 높이가 다른 곳은 렌더 값)', (tester) async {
      await pump(tester);
      await scrollToEnd(tester);
      await tester.drag(_list, const Offset(0, 3000));
      await tester.pumpAndSettle();

      void expectStyle(String text, double size, FontWeight weight, Color color, double lineBox) {
        final style = tester.widget<Text>(find.text(text)).style!;
        expect((style.fontSize, style.fontWeight, style.color), (size, weight, color), reason: text);
        expect(style.fontSize! * style.height!, closeTo(lineBox, 0.01), reason: text);
      }

      expectStyle('여우, 23', 24, FontWeight.w700, AppColors.ink, 37);
      expectStyle('가나대학교 · 경영학과', 14, FontWeight.w400, AppColors.muted, 22);
      expectStyle('학생 인증', 11, FontWeight.w600, AppColors.onInk, 18);
      expectStyle('상대에게는 이렇게 보여요', 14, FontWeight.w600, AppColors.ink, 22);
      expectStyle('AI 아바타', 11, FontWeight.w600, AppColors.onInk, 18);
      expectStyle('서로 수락하면 전달돼요', 14, FontWeight.w600, AppColors.ink, 22);
      expectStyle('수락 후 공개', 11, FontWeight.w600, AppColors.onInk, 18);
      await tester.scrollUntilVisible(find.text('학과'), 200, scrollable: _list);
      expectStyle('내 키', 14, FontWeight.w400, AppColors.muted, 21);
      expectStyle('178cm', 14, FontWeight.w600, AppColors.ink, 21);
      await scrollToEnd(tester);
      expectStyle('자기소개', 14, FontWeight.w600, AppColors.ink, 21);
      expectStyle(_bio, 16, FontWeight.w400, AppColors.body, 25);
    });

    testWidgets('아이콘 크기·색은 pen 값과 같다', (tester) async {
      await pump(tester);
      await tester.scrollUntilVisible(find.text('학과'), 200, scrollable: _list);

      void expectIcon(IconData data, double size, Color color) {
        final icon = tester.widget<Icon>(find.byIcon(data).first);
        expect((icon.size, icon.color), (size, color), reason: '$data');
      }

      // Facts 19 muted(`K31sZl`·`Wb0JO`·`l6NIM`).
      expectIcon(AppIcons.badge, 19, AppColors.muted);
      expectIcon(AppIcons.graduationCap, 19, AppColors.muted);
      await tester.drag(_list, const Offset(0, 3000));
      await tester.pumpAndSettle();
      // 배지 아이콘 13(`l6y7cm`)·12(`CRZX0` sparkles, `E2kWIB` lock), 흰색.
      expectIcon(AppIcons.badgeCheck, 13, AppColors.onInk);
      expectIcon(AppIcons.sparkles, 12, AppColors.onInk);
      expectIcon(AppIcons.lock, 12, AppColors.onInk);
    });
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 깨지지 않는다.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('pen 프레임 폭 360·글자 배율 $scale 에서 어느 줄도 넘치지 않는다', (tester) async {
      // 테스트 글꼴은 한글이 Pretendard 보다 넓다 — 여기서 버티면 실제 폰에서도 버틴다.
      usePenFrame(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(tester);
      expect(tester.takeException(), isNull);
      await scrollToEnd(tester);

      expect(tester.takeException(), isNull);
    });
  }

  // 1.3 은 검토에서 size.width 로 재면 "여우, 23" 을 잘렸다고 잘못 세던 배율이다.
  for (final scale in [1.3, 2.0]) {
  testWidgets('글자 배율 $scale 에서 어떤 글자도 고정 상자에 잘리지 않는다(스크롤 전·끝 두 번)', (tester) async {
    // 넘침 오류는 Flex 만 낸다 — SizedBox·Container 높이에 갇힌 글자는 오류 없이 잘린다.
    usePenFrame(tester);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // 앱바·내비까지 화면 전체를 본다. 내비 "커뮤니티" 는 칸 폭 안에서 일부러 말줄임한다.
    List<String> clippedTexts() => [
          for (final element in find.byType(RichText).evaluate())
            if (element.renderObject case final RenderParagraph p
                when p.text.toPlainText() != '커뮤니티' &&
                    // 폭은 배치 때 받은 최대 폭으로 잰다 — size.width 로 재면 소수점 오차로 한 줄이 두 줄로 세어진다.
                    (p.getMaxIntrinsicHeight(p.constraints.maxWidth) > p.size.height + 0.5 ||
                        p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5))
              p.text.toPlainText(),
        ];

    await pump(tester);
    final clipped = clippedTexts();
    await scrollToEnd(tester);
    clipped.addAll(clippedTexts());
    // 넘침은 위 배율 테스트가 본다 — 여기서는 잘림만 본다.
    tester.takeException();

    expect(clipped, isEmpty);
  });
  }
}
