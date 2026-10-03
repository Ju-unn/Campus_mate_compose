import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/profile_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// 사진 요청을 받기만 하고 답하지 않는 HttpClient — 화면 15 테스트와 같은 이유(그림은 "아직 오는 중").
class _PendingHttpClient extends Mock implements HttpClient {}

class _PendingHttpOverrides extends HttpOverrides {
  _PendingHttpOverrides(this._client);

  final HttpClient _client;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _client;
}

const _avatarUrl = 'https://img.test/avatar.png';
const _pillLabel = '다시 만들기 · 10';

/// 이름·학교는 지어낸 값이다.
MyProfile _profile({
  String nickname = '여우',
  int? age = 23,
  String university = '가나대학교',
  String? major = '경영학과',
  String? avatarUrl = _avatarUrl,
  int avatarRegenCost = 10,
}) =>
    MyProfile(
      nickname: nickname,
      age: age,
      university: university,
      major: major,
      heightCm: 178,
      mbti: 'ENFP',
      avatarUrl: avatarUrl,
      preferredAgeMin: 22,
      preferredAgeMax: 27,
      preferredHeightMin: 165,
      preferredHeightMax: 180,
      bio: '소개',
      avatarRegenCost: avatarRegenCost,
    );

final _hero = find.byType(ProfileHero);

/// [url] 그림을 decoration 으로 깐 상자.
Finder _imageBox(String url) => find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).image?.image == NetworkImage(url),
    );

/// [of] 를 품은, 채움이 [color] 인 상자.
Finder _fill(Color color, {required Finder of}) => find.ancestor(
      of: of,
      matching: find.byWidgetPredicate(
        (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == color,
      ),
    );

final _scrim = find.byWidgetPredicate(
  (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).gradient != null,
);

/// 알약의 보이는 몸통(흰 · 회색 알약을 칠하는 Material).
final _pill = find.ancestor(of: find.text(_pillLabel), matching: find.byType(Material)).first;

/// 알약의 누름 칸.
final _pillTapTarget = find.ancestor(of: find.text(_pillLabel), matching: find.byType(GestureDetector)).last;

final _heart = find.byWidgetPredicate(
  (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/images/heart-flat-vector-v3.png',
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

  /// 화면 15 자리(`nrcYh` 좌우 16 · 위 8) 그대로, 폭 360 프레임에 히어로 하나. [width] 는 줄 정렬을 볼 때만 넓힌다.
  Future<void> pump(
    WidgetTester tester, {
    MyProfile? profile,
    VoidCallback? onRegenerate,
    double scale = 1.0,
    double width = 360,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [ProfileHero(profile: profile ?? _profile(), onRegenerate: onRegenerate)],
          ),
        ),
      ),
    );
  }

  /// 히어로 왼쪽 위를 (0, 0) 으로 본 자리.
  Offset at(WidgetTester tester, Finder finder) => tester.getTopLeft(finder) - tester.getTopLeft(_hero);

  void expectStyle(WidgetTester tester, String text, double size, FontWeight weight, Color color, double lineHeight) {
    final style = tester.widget<Text>(find.text(text)).style!;
    expect((style.fontSize, style.fontWeight, style.color, style.height), (size, weight, color, lineHeight), reason: text);
  }

  group('틀 `l8p6X`', () {
    testWidgets('328×360, 모서리 24 로 잘라 그린다', (tester) async {
      await pump(tester, onRegenerate: () {});

      expect(tester.getSize(_hero), const Size(328, 360));
      final clip = tester.widget<ClipRRect>(find.descendant(of: _hero, matching: find.byType(ClipRRect)).first);
      expect(clip.borderRadius, BorderRadius.circular(AppRadius.lg));
    });

    testWidgets('아바타 그림은 히어로 전체를 꽉 채워 자른다(cover)', (tester) async {
      await pump(tester, onRegenerate: () {});

      final picture = _imageBox(_avatarUrl);
      expect(tester.getRect(picture), tester.getRect(_hero));
      expect((tester.widget<DecoratedBox>(picture).decoration as BoxDecoration).image!.fit, BoxFit.cover);
    });

    testWidgets('스크림 `gyzqh` — y150 부터 아래 끝까지 #222222 α 0 · 0.45 · 0.65 · 0.85 @ 0 · 0.35 · 0.6 · 1(위 → 아래)', (tester) async {
      await pump(tester, onRegenerate: () {});

      expect(at(tester, _scrim), const Offset(0, 150));
      expect(tester.getSize(_scrim), const Size(328, 210));
      final gradient = (tester.widget<DecoratedBox>(_scrim).decoration as BoxDecoration).gradient! as LinearGradient;
      expect((gradient.begin, gradient.end), (Alignment.topCenter, Alignment.bottomCenter));
      expect(gradient.stops, [0, 0.35, 0.6, 1]);
      expect(gradient.colors, [
        for (final alpha in [0.0, 0.45, 0.65, 0.85]) AppColors.surfaceInk.withValues(alpha: alpha),
      ]);
    });

    testWidgets('"AI 아바타" 배지는 없다', (tester) async {
      await pump(tester, onRegenerate: () {});

      expect(find.text('AI 아바타'), findsNothing);
      expect(find.byIcon(AppIcons.sparkles), findsNothing);
    });
  });

  group('보기 칩 `h9sFd`', () {
    testWidgets('eye 14 흰색 + "상대에게 이렇게 보여요" 13/600 흰색 lh1.5, #222222 불투명 알약, 위 16 · 왼쪽 16', (tester) async {
      await pump(tester, onRegenerate: () {});

      final chip = _fill(AppColors.surfaceInk, of: find.text('상대에게 이렇게 보여요')).first;
      expect(at(tester, chip), const Offset(16, 16));
      final decoration = tester.widget<DecoratedBox>(chip).decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.pill));
      // 패딩 [6,10] — 높이 = 6 + 글자 한 줄 + 6.
      expect(tester.getSize(chip).height, 6 + tester.getSize(find.text('상대에게 이렇게 보여요')).height + 6);
      final icon = tester.widget<Icon>(find.byIcon(AppIcons.eye));
      expect((icon.size, icon.color), (14, AppColors.onInk));
      expect(tester.getTopLeft(find.byIcon(AppIcons.eye)).dx - tester.getTopLeft(chip).dx, 10);
      // 아이콘 14 → 4 → 글자.
      expect(tester.getTopLeft(find.text('상대에게 이렇게 보여요')).dx - tester.getTopRight(find.byIcon(AppIcons.eye)).dx, 4);
      expectStyle(tester, '상대에게 이렇게 보여요', 13, FontWeight.w600, AppColors.onInk, 1.5);
    });
  });

  group('인증 배지 `EQjrL`(위쪽 줄 `dd4Jv` 오른쪽)', () {
    Finder badge() => _fill(AppColors.canvas, of: find.text('학생 인증')).first;

    testWidgets('위쪽 줄 space_between — 칩은 왼쪽, 배지는 오른쪽 끝(16 안쪽), 둘은 세로 가운데', (tester) async {
      // 폭 360 에선 테스트 글꼴로 칩이 두 줄로 꺾여 줄이 꽉 찬다(남는 공간 0) — 정렬을 보려면 빈 공간이 있어야 한다.
      // 폭 420 → 히어로 388.
      await pump(tester, onRegenerate: () {}, width: 420);

      final chip = _fill(AppColors.surfaceInk, of: find.text('상대에게 이렇게 보여요')).first;
      final hero = tester.getRect(_hero);
      expect(hero.width, 388);
      expect(tester.getTopLeft(chip).dx - hero.left, 16);
      expect(tester.getTopRight(badge()).dx, hero.right - 16);
      // 칩과 배지 사이에 최소 간격 8 보다 넓은 빈 공간이 있다 — 이 테스트가 줄이 꽉 차서 통과하는 게 아니다.
      expect(tester.getTopLeft(badge()).dx - tester.getTopRight(chip).dx, greaterThan(8));
      expect(tester.getCenter(badge()).dy, closeTo(tester.getCenter(chip).dy, 0.01));
      expect(tester.getTopLeft(badge()).dx, greaterThan(tester.getTopRight(chip).dx));
    });

    testWidgets('흰 알약 · 그림자 #34223A24 y2 blur8 · 패딩 [6,10] · 3D badge-check 18 → 4 → "학생 인증" 11/600 ink', (tester) async {
      await pump(tester, onRegenerate: () {});

      final decoration = tester.widget<DecoratedBox>(badge()).decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.pill));
      expect(decoration.boxShadow, const [BoxShadow(color: Color(0x2434223A), offset: Offset(0, 2), blurRadius: 8)]);
      final icon3d = find.descendant(of: badge(), matching: find.byType(Icon3d));
      expect(icon3d, findsOneWidget);
      expect((tester.widget<Icon3d>(icon3d).icon, tester.widget<Icon3d>(icon3d).size), (AppIcon3d.badgeCheck, 18));
      expect(find.byIcon(AppIcons.badgeCheck), findsNothing, reason: '옛 Lucide 배지 아이콘은 없다');
      // 아이콘 18 이 글자보다 높아 높이 = 6 + 18 + 6.
      expect(tester.getSize(badge()).height, 6 + 18 + 6);
      expect(tester.getTopLeft(icon3d).dx - tester.getTopLeft(badge()).dx, 10);
      expect(tester.getTopLeft(find.text('학생 인증')).dx - tester.getTopRight(icon3d).dx, 4);
      expect(tester.getTopRight(badge()).dx - tester.getTopRight(find.text('학생 인증')).dx, 10);
      final style = tester.widget<Text>(find.text('학생 인증')).style!;
      expect((style.fontSize, style.fontWeight, style.color), (11, FontWeight.w600, AppColors.ink));
    });
  });

  group('이름 묶음 `IUcwD`', () {
    testWidgets('닉네임 `CM0QK` "닉네임, 나이" 24/700 흰색 lh1.35, 이름 줄 `fXWlF` 에 배지는 없다', (tester) async {
      await pump(tester, onRegenerate: () {});

      expectStyle(tester, '여우, 23', 24, FontWeight.w700, AppColors.onInk, 1.35);
      // 배지는 보기 칩과 같은 위쪽 줄에 있다(칩 안쪽 Row 가 first, 위쪽 줄이 last).
      final topRow = find.ancestor(of: find.text('상대에게 이렇게 보여요'), matching: find.byType(Row)).last;
      expect(find.descendant(of: topRow, matching: find.text('학생 인증')), findsOneWidget);
      expect(tester.getBottomLeft(find.text('학생 인증')).dy, lessThan(tester.getTopLeft(find.text('여우, 23')).dy));
    });

    testWidgets('학교 `C9JEi` "학교 · 학과" 14/400 흰색 lh1.55 한 줄 말줄임, 12 뒤 알약', (tester) async {
      await pump(tester, onRegenerate: () {});

      expectStyle(tester, '가나대학교 · 경영학과', 14, FontWeight.w400, AppColors.onInk, 1.55);
      final school = tester.widget<Text>(find.text('가나대학교 · 경영학과'));
      expect((school.maxLines, school.overflow), (1, TextOverflow.ellipsis));
      expect(tester.getTopLeft(_pill).dx - tester.getTopRight(find.text('가나대학교 · 경영학과')).dx, greaterThanOrEqualTo(12));
      // 알약은 오른쪽 끝(학교 칸이 fill).
      expect(tester.getTopRight(_pill).dx - tester.getTopLeft(_hero).dx, 328 - 16);
    });

    testWidgets('아래 20 · 이름 줄 ↔ 학교 줄 2 · 학교 글자는 알약 높이 34 안에서 세로 가운데', (tester) async {
      await pump(tester, onRegenerate: () {});

      final pill = tester.getRect(_pill);
      expect(pill.bottom - tester.getTopLeft(_hero).dy, 360 - 20);
      expect(pill.left - tester.getTopLeft(_hero).dx, greaterThan(16));
      final nameBottom = tester.getBottomLeft(find.text('여우, 23')).dy;
      expect(pill.top - nameBottom, 2);
      expect(tester.getCenter(find.text('가나대학교 · 경영학과')).dy, closeTo(pill.center.dy, 0.01));
      expect(tester.getTopLeft(find.text('여우, 23')).dx - tester.getTopLeft(_hero).dx, 16);
    });

    testWidgets('나이 · 학과가 없으면 그 부분만 뺀다', (tester) async {
      await pump(tester, profile: _profile(age: null, major: null), onRegenerate: () {});

      expect(find.text('여우'), findsOneWidget);
      expect(find.text('가나대학교'), findsOneWidget);
      // 배지는 늘 보인다 — 이 API 는 인증된 사람만 닿는다.
      expect(find.text('학생 인증'), findsOneWidget);
    });
  });

  group('다시 만들기 알약 `R5Quru`', () {
    testWidgets('높이 34 흰 알약, 좌우 10 · 하트 16(heart-flat-vector-v3) → 4 → 13/600 primary-text lh1.5', (tester) async {
      await pump(tester, onRegenerate: () {});

      final material = tester.widget<Material>(_pill);
      expect((material.color, material.shape), (AppColors.canvas, const StadiumBorder()));
      expect(tester.getSize(_pill).height, 34);
      expect(_heart, findsOneWidget);
      expect(tester.getSize(_heart), const Size(16, 16));
      expect(tester.getTopLeft(_heart).dx - tester.getTopLeft(_pill).dx, 10);
      expect(tester.getTopLeft(find.text(_pillLabel)).dx - tester.getTopRight(_heart).dx, 4);
      expect(tester.getTopRight(_pill).dx - tester.getTopRight(find.text(_pillLabel)).dx, 10);
      expectStyle(tester, _pillLabel, 13, FontWeight.w600, AppColors.primaryText, 1.5);
    });

    testWidgets('글자 10 은 pen 고정이다 — 무료 차례(비용 0)에도 "· 10"(D6)', (tester) async {
      await pump(tester, profile: _profile(avatarRegenCost: 0), onRegenerate: () {});

      expect(find.text(_pillLabel), findsOneWidget);
    });

    testWidgets('누름 칸은 44 — 알약 아래(히어로 아래 여백 쪽)로 10 늘고, 어디를 눌러도 한 번만 불린다', (tester) async {
      var taps = 0;
      await pump(tester, onRegenerate: () => taps++);

      final pill = tester.getRect(_pill);
      final target = tester.getRect(_pillTapTarget);
      expect(target.height, 44);
      expect((target.top, target.left, target.right), (pill.top, pill.left, pill.right));

      await tester.tapAt(pill.center);
      expect(taps, 1);
      // 알약 아래 5 — 보이는 알약 밖이지만 누름 칸 안.
      await tester.tapAt(Offset(pill.center.dx, pill.bottom + 5));
      expect(taps, 2);
      // 누름 칸 밖(히어로 아래 끝 쪽)은 안 불린다.
      await tester.tapAt(Offset(pill.center.dx, target.bottom + 3));
      expect(taps, 2);
    });

    testWidgets('눌림 효과는 보이는 알약 크기의 Material 이 그린다(COMMON §4-2)', (tester) async {
      await pump(tester, onRegenerate: () {});

      final ink = find.ancestor(of: find.text(_pillLabel), matching: find.byType(InkWell));
      expect(tester.getSize(ink), tester.getSize(_pill));
      expect(tester.widget<InkWell>(ink).customBorder, const StadiumBorder());
    });

    testWidgets('15-2 비활성(`EAqjZ`, onRegenerate null) — #E5E5E5 · 하트 숨김 · 글자 #929292 · 문구 그대로, 누를 곳이 없다',
        (tester) async {
      await pump(tester, onRegenerate: null);

      expect(tester.widget<Material>(_pill).color, AppColors.primaryDisabled);
      expect(_heart, findsNothing);
      expect(find.text(_pillLabel), findsOneWidget);
      expectStyle(tester, _pillLabel, 13, FontWeight.w600, AppColors.disabled, 1.5);
      final ink = find.ancestor(of: find.text(_pillLabel), matching: find.byType(InkWell));
      expect(tester.widget<InkWell>(ink).onTap, isNull);
      expect(tester.widget<GestureDetector>(_pillTapTarget).onTap, isNull);
      // 하트가 빠진 만큼 줄어든다(pen 109 = 129 - 16 - 4) — 좌우 10 은 그대로.
      expect(tester.getTopLeft(find.text(_pillLabel)).dx - tester.getTopLeft(_pill).dx, 10);
    });
  });

  group('화면 읽기 — 알약은 버튼 하나로 한 번만 멈춘다(15b 검토 권고 1 과 같은 병)', () {
    testWidgets('켜진 알약: "하트" 가 버튼 라벨 안에 들고, 하트만 따로 떨어진 노드가 없다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, onRegenerate: () {});

      final node = tester.getSemantics(find.text(_pillLabel));
      // 재화 글리프는 Semantics(label: '하트')(CLAUDE.md §7) — 버튼 안에 합쳐 "하트 다시 만들기 · 10" 으로 한 번 읽는다.
      expect(node.label, '하트\n$_pillLabel');
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(node.childrenCount, 0);
      expect(find.bySemanticsLabel('하트'), findsNothing);
      expect(find.bySemanticsLabel(RegExp(_pillLabel)), findsOneWidget);
      // 아래 10 을 받는 누름 칸은 화면 읽기에서 빠진다 — 빠지지 않으면 탭 동작이 둘로 갈라진다.
      expect(tester.widget<GestureDetector>(_pillTapTarget).excludeFromSemantics, isTrue);
      handle.dispose();
    });

    testWidgets('꺼진 알약: 누를 수 없는 버튼 하나, 하트는 없다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, onRegenerate: null);

      final node = tester.getSemantics(find.text(_pillLabel));
      expect(node.label, _pillLabel);
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });

  testWidgets('아바타가 없으면 같은 크기 surface-soft 빈 칸, 칩 · 닉네임 · 학교 · 스크림은 그대로(Review Focus 5 · N9)', (tester) async {
    await pump(tester, profile: _profile(avatarUrl: null), onRegenerate: () {});

    final blank = find.descendant(
      of: _hero,
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == AppColors.surfaceSoft,
      ),
    );
    expect(tester.getRect(blank), tester.getRect(_hero));
    expect((tester.widget<DecoratedBox>(blank).decoration as BoxDecoration).image, isNull);
    expect(tester.getSize(_hero), const Size(328, 360));
    // 흰 글자가 밝은 빈 칸 위에서도 읽히는 것은 스크림 덕이다 — 빈 칸에도 그대로 깐다.
    expect(_scrim, findsOneWidget);
    for (final text in ['상대에게 이렇게 보여요', '여우, 23', '학생 인증', '가나대학교 · 경영학과', _pillLabel]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  // Review Focus 4 — 긴 닉네임 · 긴 학교 · 글자 배율. 학교만 말줄임하고 나머지는 줄을 바꿔 다 보인다.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('긴 닉네임 · 긴 학교 · 배율 $scale — 학교만 말줄임, 넘침 0, 알약 누름 44', (tester) async {
      const school = '가나다라마바사아자차카타파하대학교 · 아주아주긴이름의학과';
      await pump(
        tester,
        profile: _profile(nickname: '가나다라마바사아자차', university: '가나다라마바사아자차카타파하대학교', major: '아주아주긴이름의학과'),
        onRegenerate: () {},
        scale: scale,
      );

      expect(tester.takeException(), isNull);
      // 넘침 오류는 Flex 만 낸다 — 고정 상자에 갇힌 글자는 오류 없이 잘린다. 학교 줄만 일부러 말줄임한다.
      final clipped = <String>[];
      var schoolEllipsized = false;
      for (final element in find.descendant(of: _hero, matching: find.byType(RichText)).evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        final text = paragraph.text.toPlainText();
        if (text == school) {
          schoolEllipsized = paragraph.didExceedMaxLines;
          continue;
        }
        final cut = paragraph.getMaxIntrinsicHeight(paragraph.constraints.maxWidth) > paragraph.size.height + 0.5 ||
            paragraph.getMinIntrinsicWidth(double.infinity) > paragraph.size.width + 0.5;
        if (cut) clipped.add(text);
      }
      expect(clipped, isEmpty);
      expect(schoolEllipsized, isTrue);
      expect(tester.getSize(_pillTapTarget).height, greaterThanOrEqualTo(44));
      // 알약 · 이름 묶음이 히어로 안에 있다.
      expect(tester.getRect(_hero).contains(tester.getRect(_pillTapTarget).bottomRight - const Offset(0.5, 0.5)), isTrue);
      expect(tester.getTopLeft(find.text('상대에게 이렇게 보여요')).dy, greaterThan(tester.getTopLeft(_hero).dy));
    });
  }
}
