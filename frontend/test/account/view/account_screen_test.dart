import 'dart:async';
import 'dart:io';

import 'package:campus_mate/account/model/account_info.dart';
import 'package:campus_mate/account/model/account_repository.dart';
import 'package:campus_mate/account/view/account_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/icon_3d.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../model/fake_account_repository.dart';

/// 로고 요청을 받기만 하고 답하지 않는 HttpClient — 로고는 "아직 오는 중"이라 자리만 잡는다(히어로 테스트와 같은 방식).
class _PendingHttpClient extends Mock implements HttpClient {}

class _PendingHttpOverrides extends HttpOverrides {
  _PendingHttpOverrides(this._client);

  final HttpClient _client;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _client;
}

const _logoUrl = 'https://logo.test/snu.webp';

/// 학교 로고 그림(간격 Padding 을 뺀 16×16 자리).
final _logo = find.descendant(
  of: find.byWidgetPredicate((w) => w is Image && w.image == const NetworkImage(_logoUrl)),
  matching: find.byType(RawImage),
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

  Future<FakeAccountRepository> pump(
    WidgetTester tester, {
    FakeAccountRepository? repository,
    Map<String, String> logos = const {'서울대학교': _logoUrl},
  }) async {
    final fake = repository ?? FakeAccountRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(fake),
        universityLogosProvider.overrideWith((ref) => logos),
      ],
      child: const MaterialApp(home: AccountScreen()),
    ));
    // 로고 그림은 끝나지 않는 요청이라 pumpAndSettle 은 그림 쪽을 기다리지 않는다.
    await tester.pumpAndSettle();
    return fake;
  }

  AccountInfo info({String? realName, int? birthYear, String? kakaoId, DateTime? joinedAt}) => AccountInfo(
        email: 'hong@snu.ac.kr', realName: realName, birthYear: birthYear, university: '서울대학교',
        joinedAt: joinedAt ?? DateTime.utc(2026, 9, 1, 10), kakaoId: kakaoId,
      );

  testWidgets('로그인 · 본인 확인 · 연락처 · 가입 값이 보인다', (tester) async {
    await pump(tester);

    expect(find.text('hong@snu.ac.kr'), findsOneWidget);
    expect(find.text('인증 완료'), findsOneWidget);
    expect(find.text('홍길동'), findsOneWidget);
    expect(find.text('2003'), findsOneWidget); // pen EYBxA — 숫자만
    expect(find.text('서울대학교'), findsOneWidget);
    expect(find.text('2026.09.01'), findsOneWidget); // pen nntyt
    expect(find.text('fox_rain'), findsOneWidget);
    expect(find.text(AccountScreen.privacyNote), findsOneWidget);
  });

  testWidgets('줄마다 pen 의 3D 그림이 그 순서로, 크기 22 로 그려진다(pen `huZA9` · `shH3F` · `PkqpC` · `H62oC` · `E5TUHj` · `Lua1H` · `UCEwf`)', (tester) async {
    await pump(tester);

    final icons = tester.widgetList<Icon3d>(find.byType(Icon3d)).toList();
    expect([for (final icon in icons) icon.icon], [
      AppIcon3d.mail,
      AppIcon3d.badgeCheck,
      AppIcon3d.userRound,
      AppIcon3d.calendar,
      AppIcon3d.graduationCap,
      AppIcon3d.chat,
      AppIcon3d.calendarCheck,
    ]);
    for (final icon in icons) {
      expect(icon.size, 22);
    }
  });

  testWidgets('구역 순서는 pen n8lZI 대로 — 안내문은 본인 확인 정보 바로 아래', (tester) async {
    await pump(tester);

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('로그인 정보'), lessThan(top('본인 확인 정보')));
    expect(top('학교'), lessThan(top(AccountScreen.privacyNote)));
    expect(top(AccountScreen.privacyNote), lessThan(top('연락처 공개 정보')));
    expect(top('연락처 공개 정보'), lessThan(top('가입 정보')));
  });

  testWidgets('가입일은 기기 시간대가 아니라 한국 날짜다', (tester) async {
    // UTC 8/31 16:00 = 한국 9/1 01:00.
    await pump(tester, repository: (FakeAccountRepository()..accountResult = Success(info(joinedAt: DateTime.utc(2026, 8, 31, 16)))));

    expect(find.text('2026.09.01'), findsOneWidget);
  });

  testWidgets('빈 값은 "—" 로 그린다', (tester) async {
    await pump(tester, repository: (FakeAccountRepository()..accountResult = Success(info())));

    expect(tester.takeException(), isNull);
    // 상수가 아니라 글자로 찾는다 — 상수를 '' 로 바꿔도 통과하던 검토 R0 권고 1.
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('값은 카드 안쪽 오른쪽 끝에 붙는다 — pen 라벨 fill · 값 hug', (tester) async {
    usePenFrame(tester);
    await pump(tester);

    // 360 − 목록 좌우 16 − 줄 좌우 14. 글자 상자로 잰다(Text 상자는 정렬과 무관하게 칸을 채울 수 있다).
    const cardInnerRight = 330.0;
    double lastGlyphRight(String value) {
      final p = tester.renderObject<RenderParagraph>(find.text(value));
      final last = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: value.length)).last;
      return p.localToGlobal(Offset(last.right, 0)).dx;
    }

    for (final value in ['hong@snu.ac.kr', '인증 완료', '홍길동', '2003', '서울대학교', '2026.09.01']) {
      expect(lastGlyphRight(value), closeTo(cardInnerRight, 0.5), reason: value);
    }
    // 카톡 줄은 셰브런(18)이 끝에 붙고, 값은 줄 간격 12 앞에서 끝난다.
    expect(tester.getRect(find.byIcon(AppIcons.chevronRight)).right, cardInnerRight);
    expect(lastGlyphRight('fox_rain'), closeTo(cardInnerRight - 18 - 12, 0.5));
  });

  group('학교 값 `SQQa9` · `FNU1J`(School Symbol)', () {
    testWidgets('로고 16 → 4 → "서울대학교" 한 줄, 값 스타일(14 muted) 그대로, 오른쪽 끝에 붙는다', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final label = tester.widget<SchoolLabel>(find.byType(SchoolLabel));
      expect(label.university, '서울대학교');
      expect(label.style, AppTypography.bodySmall.copyWith(color: AppColors.muted));
      expect(tester.getSize(_logo), const Size(16, 16));
      final text = tester.getRect(find.text('서울대학교'));
      expect(text.left - tester.getTopRight(_logo).dx, 4);
      // 테스트 글꼴은 줄 높이 21.7 을 22 로 반올림해 0.15 어긋난다.
      expect(tester.getCenter(_logo).dy, closeTo(text.center.dy, 0.5), reason: '한 줄이면 로고는 줄 가운데');
      // 로고는 "학교" 라벨과 같은 줄, 라벨보다 오른쪽.
      expect(tester.getTopLeft(_logo).dx, greaterThan(tester.getTopRight(find.text('학교')).dx));
      expect(tester.getCenter(_logo).dy, closeTo(tester.getCenter(find.text('학교')).dy, 1));
    });

    testWidgets('두 줄로 접혀도 두 줄 다 오른쪽 끝, 로고는 첫 줄 바로 앞 4', (tester) async {
      usePenFrame(tester);
      // 지어낸 긴 학교 이름 — 값 칸에서 두 줄로 접힌다.
      const school = '가나다라마바사대학교 아자차카타파하캠퍼스';
      final account = AccountInfo(
        email: 'hong@snu.ac.kr', realName: null, birthYear: null, university: school,
        joinedAt: DateTime.utc(2026, 9, 1, 10), kakaoId: null,
      );
      await pump(
        tester,
        repository: FakeAccountRepository()..accountResult = Success(account),
        logos: const {school: _logoUrl},
      );

      final p = tester.renderObject<RenderParagraph>(find.text(school));
      final lines = <double, List<TextBox>>{};
      for (final box in p.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: school.length))) {
        lines.putIfAbsent(box.top, () => []).add(box);
      }
      expect(lines, hasLength(2), reason: '두 줄이어야 이 테스트가 뜻이 있다');
      for (final line in lines.values) {
        expect(p.localToGlobal(Offset(line.last.right, 0)).dx, closeTo(330, 0.5));
      }
      final firstLineLeft = p.localToGlobal(Offset(lines.values.first.first.left, 0)).dx;
      expect(firstLineLeft - tester.getTopRight(_logo).dx, closeTo(4, 0.5));
    });

    testWidgets('로고가 없는 학교는 글자만, 그대로 오른쪽 끝', (tester) async {
      usePenFrame(tester);
      await pump(tester, logos: const {});

      expect(_logo, findsNothing);
      expect(find.text('서울대학교'), findsOneWidget);
      expect(tester.getTopRight(find.text('서울대학교')).dx, closeTo(330, 0.5));
    });

    testWidgets('다른 줄 값에는 로고가 없다', (tester) async {
      await pump(tester);

      expect(find.byType(SchoolLabel), findsOneWidget);
    });
  });

  testWidgets('카카오톡 줄만 누를 수 있고 셰브런이 붙는다(pen ow0m3)', (tester) async {
    await pump(tester);

    final row = find.byType(InkWell);
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('카카오톡 아이디')), findsOneWidget);
    final chevron = find.descendant(of: row, matching: find.byIcon(AppIcons.chevronRight));
    expect(chevron, findsOneWidget);
    expect(tester.widget<Icon>(chevron).size, 18);
    expect(tester.widget<Icon>(chevron).color, AppColors.muted);
  });

  testWidgets('카카오톡 줄의 눌림 효과는 그 카드 안에서 그려진다', (tester) async {
    // 잉크는 가장 가까운 Material 에 그린다 — 카드 밖 Material(Scaffold)이면 모서리 밖까지 번진다(COMMON §4-2).
    await pump(tester);

    final row = find.byType(InkWell);
    final material = find.ancestor(of: row, matching: find.byType(Material)).first;
    expect(tester.getSize(material), tester.getSize(row));
  });

  group('카카오톡 줄 → 16e-1(T3)', () {
    late FakeAccountRepository fake;
    late GoRouter router;

    Future<void> openKakaoIdSettings(WidgetTester tester) async {
      fake = FakeAccountRepository();
      router = GoRouter(
        initialLocation: AppRoutes.account,
        routes: [
          GoRoute(path: AppRoutes.account, builder: (context, state) => const AccountScreen()),
          GoRoute(path: AppRoutes.kakaoIdSettings, builder: (context, state) => const Scaffold(body: Text('16e-1'))),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [accountRepositoryProvider.overrideWithValue(fake)],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      expect(fake.accountFetches, 1);

      await tester.ensureVisible(find.text('카카오톡 아이디'));
      await tester.tap(find.text('카카오톡 아이디'));
      await tester.pumpAndSettle();
      expect(find.text('16e-1'), findsOneWidget);
      // 16e-1 이 열려 있는 동안은 다시 읽지 않는다 — 닫힌 뒤에 읽어야 저장한 아이디가 보인다(검토 R2 권고 1).
      expect(fake.accountFetches, 1);
    }

    testWidgets('저장하고 돌아오면 다시 읽는다', (tester) async {
      await openKakaoIdSettings(tester);

      router.pop(true); // 16e-1 은 저장하면 true 를 들고 닫힌다.
      await tester.pumpAndSettle();

      expect(find.byType(AccountScreen), findsOneWidget);
      expect(fake.accountFetches, 2);
    });

    testWidgets('저장하지 않고 돌아오면 다시 읽지 않는다 — 실명이 든 GET 을 한 번 덜 부른다', (tester) async {
      await openKakaoIdSettings(tester);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(AccountScreen), findsOneWidget);
      expect(fake.accountFetches, 1);
    });
  });

  testWidgets('못 불러오면 다시 시도할 수 있다', (tester) async {
    final fake = await pump(tester, repository: (FakeAccountRepository()..accountResult = const FailureResult(NetworkFailure())));
    expect(find.text('잠시 뒤 다시 시도해 주세요'), findsOneWidget);

    fake.accountResult = Success(sampleAccount);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(fake.accountFetches, 2);
    expect(find.text('홍길동'), findsOneWidget);
  });

  // DESIGN §11.2 — 넘침(Flex 오류)과 잘림(오류 없이 글자가 상자 밖)을 따로 본다. 기본 800 폭에선 안 보여 pen 폭 360 으로 본다.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('폭 360 · 글자 배율 $scale 에서 넘치거나 잘리는 글자가 없다', (tester) async {
      usePenFrame(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);

      expect(tester.takeException(), isNull);
      final clipped = [
        for (final element in find.byType(RichText).evaluate())
          if (element.renderObject case final RenderParagraph p when clips(p)) p.text.toPlainText(),
      ];
      expect(clipped, isEmpty);
    });
  }
}

void usePenFrame(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 세로는 받은 폭에서 필요한 높이로, 가로는 글자 상자 하나하나로 잰다 — 긴 낱말은 글자 단위로 줄을 바꾸므로
/// 낱말 폭(minIntrinsicWidth)으로 재면 안 잘린 것도 잘렸다고 센다. 줄 끝 공백 상자는 원래 폭 밖이라 뺀다.
/// maxLines · 말줄임은 높이도 상자도 그 줄 수에 맞춰 돌려줘 위 두 검사로는 안 보인다(검토 R1 권고 1).
bool clips(RenderParagraph p) {
  if (p.didExceedMaxLines) return true;
  if (p.getMaxIntrinsicHeight(p.constraints.maxWidth) > p.size.height + 0.5) return true;
  final text = p.text.toPlainText();
  for (var i = 0; i < text.length; i++) {
    if (text[i].trim().isEmpty) continue;
    final boxes = p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.any((box) => box.left < -0.5 || box.right > p.size.width + 0.5)) return true;
  }
  return false;
}
