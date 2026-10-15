import 'dart:async';
import 'dart:io';

import 'package:campus_mate/chat/model/chat_repository_provider.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/home/model/home_repository_provider.dart';
import 'package:campus_mate/home/model/home_summary.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/view/tag.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/notifications/model/notifications_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../billing/view/pretendard.dart';
import '../../chat/model/fake_chat_repository.dart';
import '../../matching/model/fake_card_repository.dart';
import '../../me/model/fake_me_repository.dart';
import '../../notifications/model/fake_notifications_repository.dart';
import '../model/fake_home_repository.dart';

/// 로고 요청을 받기만 하고 답하지 않는 HttpClient — 로고는 "아직 오는 중"이라 자리만 잡는다.
class _PendingHttpClient extends Mock implements HttpClient {}

/// 로고 요청마다 연결 오류를 내는 HttpClient — 로고를 못 불러온 경우.
class _FailingHttpClient extends Mock implements HttpClient {}

/// pen 09b 칩 줄(`zOaUW`)의 네 학교 — 내 학교(고려대)가 맨 앞이다. 로고 주소는 지어낸 값이다.
const _penSchools = ['고려대', '서울대', '연세대', '성균관대'];
Map<String, String> _logosFor(List<String> schools) => {for (final s in schools) s: 'https://logo.test/$s.webp'};

/// pen 은 글자 폭을 정수로 그리고(`aVMeb` 34 · `G4UtMu` 45, lineHeight 외 속성 없음) 같은 Pretendard 라도 Flutter 렌더가
/// 2~2.5 좁다(31.9 · 42.5). 칩 짜임(6 + 14 + 4 + 글자 + 6)은 정확히 보고, pen 폭은 이 만큼 봐준다.
const double _penTextSlack = 3;

/// 운영 `universities.name` 처럼 "…대학교" 까지 붙은 이름(supabase/seed.sql).
const _fullNames = ['고려대학교', '서울대학교', '연세대학교', '성균관대학교', '이화여자대학교', '서울시립대학교'];

Finder _chipOf(String name) => find.ancestor(of: find.text(name), matching: find.byType(Container)).first;
Finder _logoOf(String name) => find.descendant(of: _chipOf(name), matching: find.byType(RawImage));
final _logoImages = find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage);

MyProfile _me(String university) => MyProfile(
  nickname: '여우',
  age: 23,
  university: university,
  major: '경영학과',
  heightCm: 178,
  mbti: 'ENFP',
  avatarUrl: null,
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: 165,
  preferredHeightMax: 180,
  bio: '',
);

void main() {
  // 시험 기본 글꼴(Ahem)은 한글 폭이 Pretendard 와 달라 pen 칩 폭과 견줄 수 없다 — 이 파일만 Pretendard 로 잰다.
  setUpAll(() async {
    registerFallbackValue(Uri());
    await loadPretendard();
  });

  // 그림 캐시가 앞 테스트의 로고를 쥐고 있지 않게 비운다. 디버그 훅은 테스트 본문 끝에서 되돌린다(불변식 검사가 tearDown 보다 먼저다).
  setUp(() => PaintingBinding.instance.imageCache.clear());

  void useHttp([HttpClient? client]) {
    final pending = _PendingHttpClient();
    when(() => pending.getUrl(any())).thenAnswer((_) => Completer<HttpClientRequest>().future);
    debugNetworkImageHttpClientProvider = () => client ?? pending;
  }

  group('Tag 학교 로고(pen Tag `nAfU0` 인스턴스 `T2Pfi4` 등 — 안에 School Symbol `VI8eN` 등)', () {
    Future<void> pumpTag(
      WidgetTester tester,
      Widget child, {
      FutureOr<Map<String, String>> Function()? logos,
      HttpClient? client,
    }) async {
      useHttp(client);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [universityLogosProvider.overrideWith((ref) => logos == null ? _logosFor(_penSchools) : logos())],
          child: MaterialApp(
            // 칩 줄과 같이 Wrap 안에 둔다 — 세로가 열려 있어야 칩이 높이 28 로 줄어든다.
            home: Scaffold(body: Wrap(children: [child])),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('로고가 있으면 왼쪽 6 · 로고 14×14 · 사이 4 · 글자 · 오른쪽 6 — pen 칩 64×28 · 로고 x6 y7 · 글자 x24 y5 높이 18', (tester) async {
      // 로고 그림은 오는 중이다(답 없는 HttpClient) — 그동안에도 14 칸을 잡아 둬 도착해도 칩 폭이 그대로다.
      await pumpTag(tester, const Tag(label: '고려대'));

      final chip = tester.getRect(_chipOf('고려대'));
      final logo = tester.getRect(_logoOf('고려대'));
      final text = tester.getRect(find.text('고려대'));
      expect(chip.height, 28);
      expect(logo.size, const Size(14, 14));
      expect(logo.topLeft - chip.topLeft, const Offset(6, 7)); // `ebvja` x6 y5 + `k6HUy3` y2
      expect(text.left - logo.right, 4); // School Symbol gap 4
      expect((text.top - chip.top, text.height), (5, 18)); // `aVMeb` 12 · lineHeight 1.5
      expect(chip.right - text.right, 6); // Tag padding [0,6]
      expect(chip.width, text.width + 30); // 6 + 14 + 4 + 글자 + 6
      expect(chip.width, closeTo(64, _penTextSlack)); // `T2Pfi4` 렌더 폭
      debugNetworkImageHttpClientProvider = null;
    });

    testWidgets('성균관대 칩은 pen 폭 75', (tester) async {
      await pumpTag(tester, const Tag(label: '성균관대'));

      expect(tester.getSize(_chipOf('성균관대')).width, closeTo(75, _penTextSlack)); // `oCAIJ` 렌더 폭
      debugNetworkImageHttpClientProvider = null;
    });

    void expectTextOnly(WidgetTester tester, String name) {
      final chip = tester.getRect(_chipOf(name));
      final text = tester.getRect(find.text(name));
      expect(_logoOf(name), findsNothing);
      expect(chip.height, 28);
      // 로고 없는 칩은 Tag 마스터 `nAfU0` 의 padding [0,11] — 로고 몫 [0,6] 은 로고와 함께일 때만이다.
      expect((text.left - chip.left, chip.right - text.right), (11, 11));
      expect(text.top - chip.top, 5);
    }

    testWidgets('로고가 없는 학교는 글자만 · 좌우 11(Tag 마스터 `nAfU0`)', (tester) async {
      await pumpTag(tester, const Tag(label: '가람대'));

      expectTextOnly(tester, '가람대');
      debugNetworkImageHttpClientProvider = null;
    });

    testWidgets('로고 표를 아직 읽는 중이면 글자만 · 좌우 11', (tester) async {
      await pumpTag(tester, const Tag(label: '고려대'), logos: () => Completer<Map<String, String>>().future);

      expectTextOnly(tester, '고려대');
      debugNetworkImageHttpClientProvider = null;
    });

    testWidgets('로고 그림을 못 불러오면 로고 칸 · 간격까지 빼고 글자만 · 좌우 11', (tester) async {
      final client = _FailingHttpClient();
      when(() => client.getUrl(any())).thenAnswer((_) async => throw const SocketException('없음'));
      await pumpTag(tester, const Tag(label: '고려대'), client: client);
      await tester.pump();

      expectTextOnly(tester, '고려대');
      debugNetworkImageHttpClientProvider = null;
    });

    testWidgets('내 학교 칩도 같은 자리에 로고 — primary-wash 채움 · primary-text 글자(`T2Pfi4`)', (tester) async {
      await pumpTag(tester, const Tag(label: '고려대', mine: true));

      final box = tester.widget<Container>(_chipOf('고려대')).decoration! as BoxDecoration;
      expect(box.color, const Color(0xFFFFF0F2));
      expect(tester.widget<Text>(find.text('고려대')).style!.color, const Color(0xFFC4224B));
      expect(tester.getRect(_logoOf('고려대')).topLeft - tester.getTopLeft(_chipOf('고려대')), const Offset(6, 7));
      debugNetworkImageHttpClientProvider = null;
    });

    testWidgets('낭독기는 칩마다 학교 이름을 한 번만 — 로고는 읽히지 않고, 내 학교는 "내 학교" 를 앞에 붙인다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTag(
        tester,
        const Wrap(spacing: 6, children: [Tag(label: '고려대', mine: true), Tag(label: '서울대')]),
      );

      expect(_logoImages, findsNWidgets(2), reason: '두 칩 모두 로고가 있어야 이 테스트가 뜻이 있다');
      expect(tester.widgetList<Image>(_logoImages).every((image) => image.excludeFromSemantics), isTrue);
      expect(tester.getSemantics(find.bySemanticsLabel(RegExp('고려대'))).label, '내 학교\n고려대');
      expect(tester.getSemantics(find.bySemanticsLabel(RegExp('서울대'))).label, '서울대');
      handle.dispose();
      debugNetworkImageHttpClientProvider = null;
    });

    testWidgets('글자 240% — 로고는 14 그대로 글자 줄 가운데, 칩은 글자만큼 높아진다(DESIGN §11.2)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpTag(tester, const Tag(label: '고려대'));

      final text = tester.getRect(find.text('고려대'));
      final logo = tester.getRect(_logoOf('고려대'));
      // 줄 높이 12 × 2.4 × 1.5 = 43.2 — 엔진이 줄 상자를 정수 쪽으로 맞춰 43 으로 그린다.
      expect(text.height, closeTo(12 * 2.4 * 1.5, 0.5));
      expect(logo.size, const Size(14, 14));
      expect(logo.center.dy, closeTo(text.center.dy, 0.5));
      expect(tester.getSize(_chipOf('고려대')).height, text.height);
      expect(tester.takeException(), isNull);
      debugNetworkImageHttpClientProvider = null;
    });
  });

  group('campus-strip 로고 칩 줄(pen 09b `zOaUW` · 불러오는 중 `gEcCP`)', () {
    /// mosaic-rail 도 가로 Scrollable 이라 세로 목록을 짚어 준다.
    final mainList = find.byType(Scrollable).first;

    Future<void> pumpHome(WidgetTester tester, {required List<String> campuses, double width = 320}) async {
      tester.view.physicalSize = Size(width, 884);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      useHttp();
      final container = ProviderContainer(
        overrides: [
          homeRepositoryProvider.overrideWithValue(
            FakeHomeRepository(
              Success(
                HomeSummary(
                  deliveredCards: 10,
                  signups: 20,
                  conversationsStarted: 30,
                  reviewRating: 4.6,
                  reviewCount: 57,
                  campuses: campuses,
                  profileCompletionPercent: 40,
                ),
              ),
            ),
          ),
          notificationsRepositoryProvider.overrideWithValue(FakeNotificationsRepository()),
          meRepositoryProvider.overrideWithValue(FakeMeRepository(Success(_me(campuses.first)))),
          cardRepositoryProvider.overrideWithValue(FakeCardRepository()),
          chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
          universityLogosProvider.overrideWith((ref) => _logosFor(campuses)),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen())],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // 칩 줄 바로 아래 완성도 카드까지 내린다 — 흐르는 칩 줄(5개 이상)은 같은 이름이 복사본마다 있어 이름으로는 못 짚는다.
      await tester.scrollUntilVisible(find.text('프로필 완성도 40%'), 200, scrollable: mainList);
    }

    /// 칩이 화면 좌우 여백 16 안에 들어가는지.
    void expectInsideMargins(WidgetTester tester, List<String> campuses, double width) {
      for (final name in campuses) {
        final chip = tester.getRect(_chipOf(name));
        expect(chip.left, greaterThanOrEqualTo(16), reason: name);
        expect(chip.right, lessThanOrEqualTo(width - 16), reason: name);
      }
    }

    testWidgets('320 폭 폰에서 pen 네 학교 로고 칩이 한 줄 · 칩 사이 6 · 폭 64/64/64/75', (tester) async {
      await pumpHome(tester, campuses: _penSchools);

      final rects = [for (final name in _penSchools) tester.getRect(_chipOf(name))];
      for (final name in _penSchools) {
        expect(_logoOf(name), findsOneWidget, reason: name);
      }
      expect(rects.map((r) => r.top).toSet(), hasLength(1));
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].left - rects[i - 1].right, 6);
      }
      for (final (index, width) in [64.0, 64.0, 64.0, 75.0].indexed) {
        expect(rects[index].width, closeTo(width, _penTextSlack), reason: _penSchools[index]);
      }
      expectInsideMargins(tester, _penSchools, 320);
      expect(tester.takeException(), isNull);
      debugNetworkImageHttpClientProvider = null;
    });

    // 칩이 5개 이상이면 줄바꿈 대신 한 줄로 흐른다(사용자 지시 10-15, home_screen_test 'campus-strip 자동 흐름') — 줄바꿈은 4개 이하에서 본다.
    final fourFull = _fullNames.take(4).toList();

    testWidgets('"…대학교" 이름 4개는 한 줄에 다 안 들어가면 다음 줄로 흐른다 · 줄 사이 6 · 넘침 없음', (tester) async {
      await pumpHome(tester, campuses: fourFull);

      final rects = [for (final name in fourFull) tester.getRect(_chipOf(name))];
      final rows = rects.map((r) => r.top).toSet().toList()..sort();
      expect(rows.length, greaterThan(1));
      expect(rows[1] - rows[0], 28 + 6);
      expectInsideMargins(tester, fourFull, 320);
      expect(tester.takeException(), isNull);
      debugNetworkImageHttpClientProvider = null;
    });

    testWidgets('"…대학교" 이름 6개(5개 이상)는 줄을 바꾸지 않고 한 줄 · 칩 사이 6 · 넘침 없음', (tester) async {
      await pumpHome(tester, campuses: _fullNames);

      final rects = [for (final name in _fullNames) tester.getRect(_chipOf(name))];
      expect(rects.map((r) => r.top).toSet(), hasLength(1));
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].left - rects[i - 1].right, 6, reason: _fullNames[i]);
      }
      expect(tester.takeException(), isNull);
      debugNetworkImageHttpClientProvider = null;
    });

    for (final campuses in [fourFull, _fullNames]) {
      testWidgets('글자 240% · 320 폭 — 로고 칩 줄이 넘치지도 잘리지도 않는다(칩 ${campuses.length}개)', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.4;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpHome(tester, campuses: campuses);

        // 흐르는 줄(5개 이상)은 화면 밖까지 이어 붙여 좌우 여백 안에 들지 않는다 — 여백은 줄바꿈 줄에서만 본다.
        if (campuses.length < 5) expectInsideMargins(tester, campuses, 320);
        for (final name in campuses) {
          final p = tester.renderObject<RenderParagraph>(find.text(name).first);
          expect(p.getMaxIntrinsicHeight(p.size.width), lessThanOrEqualTo(p.size.height + 0.5), reason: name);
          expect(p.getMinIntrinsicWidth(double.infinity), lessThanOrEqualTo(p.size.width + 0.5), reason: name);
          expect(tester.getSize(_logoOf(name)), const Size(14, 14), reason: name);
        }
        expect(tester.takeException(), isNull);
        debugNetworkImageHttpClientProvider = null;
      });
    }
  });
}
