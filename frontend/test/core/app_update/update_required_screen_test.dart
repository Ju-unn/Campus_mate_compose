import 'dart:async';

import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/consent/model/repository/open_url.dart';
import 'package:campus_mate/core/app_update/update_required_screen.dart';
import 'package:campus_mate/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../billing/store/view/pretendard.dart';

const _storeUrl = 'https://play.google.com/store/apps/details?id=io.github.juunn.campusmate';
const _title = '새 버전으로 업데이트해 주세요';
const _description = '더 안전하고 편하게 쓸 수 있도록 앱이 바뀌었어요.\n업데이트한 뒤 다시 열어 주세요.';
const _failMessage = '스토어를 열지 못했어요. 스토어에서 CampusMate를 검색해 주세요.';

/// 스토어를 여는 창구의 가짜 — 부른 주소를 남기고, 결과를 시험이 정한다.
class _Launcher {
  final List<Uri> opened = [];
  bool result = true;
  Object? error;
  Completer<bool>? hold;

  Future<bool> call(Uri uri) async {
    opened.add(uri);
    if (error != null) throw error!;
    return hold?.future ?? result;
  }
}

void main() {
  late _Launcher launcher;

  setUpAll(loadPretendard);
  setUp(() => launcher = _Launcher());

  Future<void> pumpScreen(WidgetTester tester, {String storeUrl = _storeUrl, Size size = const Size(360, 780)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [openExternalUrlProvider.overrideWithValue(launcher.call)],
        child: MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: UpdateRequiredScreen(storeUrl: storeUrl)),
      ),
    );
  }

  /// 토스트가 떠 있는 2초를 흘려 시간 재는 장치(Timer)가 시험 뒤에 남지 않게 한다.
  Future<void> letToastGo(WidgetTester tester) => tester.pump(const Duration(seconds: 3));

  group('pen zSzOG — 글자와 그림', () {
    testWidgets('제목 · 설명 · 버튼 글자가 pen 그대로다', (tester) async {
      await pumpScreen(tester);

      expect(find.text(_title), findsOneWidget); // ZBzIg
      expect(find.text(_description), findsOneWidget); // DFs55
      expect(find.text('업데이트하러 가기'), findsOneWidget); // uJxza
    });

    testWidgets('마스코트는 파란 목도리 기다림(PKbwO) 120×120 이다', (tester) async {
      await pumpScreen(tester);

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, 'assets/images/mascot-male-waiting.png');
      expect(tester.getSize(find.byType(Image)), const Size(120, 120));
    });

    testWidgets('제목은 20/700 #222222 가운데다 (ZBzIg)', (tester) async {
      await pumpScreen(tester);

      final title = tester.widget<Text>(find.text(_title));
      expect(title.style!.fontSize, 20);
      expect(title.style!.fontWeight, FontWeight.w700);
      expect(title.style!.color, const Color(0xFF222222));
      expect(title.textAlign, TextAlign.center);
    });

    testWidgets('설명은 14/보통 #6A6A6A 줄높이 1.55 가운데다 (DFs55)', (tester) async {
      await pumpScreen(tester);

      final description = tester.widget<Text>(find.text(_description));
      expect(description.style!.fontSize, 14);
      expect(description.style!.fontWeight, FontWeight.w400);
      expect(description.style!.color, const Color(0xFF6A6A6A));
      expect(description.style!.height, 1.55);
      expect(description.textAlign, TextAlign.center);
    });

    testWidgets('설명은 312 폭에서 두 줄이다 — Empty 가로 여백이 0 이라서 (a92mlI [48,0])', (tester) async {
      await pumpScreen(tester);

      // 두 줄 = 14 × 1.55 × 2 = 43.4 (글자 상자는 줄마다 올림이라 44). 가로 여백이 기본 24 였다면 264 폭이라 세 줄(65)로 접힌다.
      expect(tester.getSize(find.text(_description)).height, closeTo(14 * 1.55 * 2, 1));
    });
  });

  group('pen zSzOG — 배치 (360×780)', () {
    testWidgets('흰 바탕이다', (tester) async {
      await pumpScreen(tester);

      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, const Color(0xFFFFFFFF));
    });

    testWidgets('안내는 위 여백 120 + 간격 20 아래, 마스코트 → 24 → 제목 → 8 → 설명 순서로 가운데에 선다', (tester) async {
      await pumpScreen(tester);

      // 안내(Empty a92mlI)는 140 에서 시작하고 안쪽 위 여백 48 뒤에 마스코트가 온다.
      expect(tester.getTopLeft(find.byKey(const ValueKey('update-notice'))).dy, 120 + 20);
      final mascot = tester.getRect(find.byType(Image));
      expect(mascot.top, 120 + 20 + 48);
      expect(mascot.center.dx, 180);
      final title = tester.getRect(find.text(_title));
      expect(title.top, mascot.bottom + 24);
      expect(title.center.dx, closeTo(180, 0.5));
      final description = tester.getRect(find.text(_description));
      expect(description.top, title.bottom + 8);
      expect(description.center.dx, closeTo(180, 0.5));
    });

    testWidgets('버튼은 312×52, 바닥에서 40 위, 좌우 24 다', (tester) async {
      await pumpScreen(tester);

      final button = tester.getRect(find.byType(ElevatedButton));
      expect(button.size, const Size(312, 52));
      expect(button.bottom, 780 - 40);
      expect(button.left, 24);
    });

    testWidgets('뒤로가기 · 닫기가 없다 — 앱바도 아이콘 버튼도 없다', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(CloseButton), findsNothing);
    });

    testWidgets('글자를 2배로 키워도 넘치지 않고 버튼은 바닥에 남는다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpScreen(tester, size: const Size(360, 640));

      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(ElevatedButton)).bottom, 640 - 40);
    });
  });

  group('스토어 열기', () {
    testWidgets('버튼을 누르면 스토어 주소를 기기 앱으로 연다', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('업데이트하러 가기'));
      await tester.pump();

      expect(launcher.opened, [Uri.parse(_storeUrl)]);
      expect(find.byType(AppToast), findsNothing);
    });

    testWidgets('열지 못하면(false) 짧은 안내를 띄우고, 2초 뒤 사라진다', (tester) async {
      launcher.result = false;
      await pumpScreen(tester);

      await tester.tap(find.text('업데이트하러 가기'));
      await tester.pump();

      expect(find.text(_failMessage), findsOneWidget);
      expect(find.byType(AppToast), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(AppToast), findsNothing);
    });

    testWidgets('안내는 버튼 위 12, 가로 가운데에 뜬다 (토스트 공통 규칙 §8.5)', (tester) async {
      launcher.result = false;
      await pumpScreen(tester);

      await tester.tap(find.text('업데이트하러 가기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // 올라오는 움직임(아래 8 → 제자리)이 끝난 뒤

      final toast = tester.getRect(find.byType(AppToast));
      expect(toast.bottom, tester.getRect(find.byType(ElevatedButton)).top - 12);
      expect(toast.center.dx, closeTo(180, 0.5));
      await letToastGo(tester);
    });

    testWidgets('기기가 예외를 던져도 같은 안내를 띄운다', (tester) async {
      launcher.error = Exception('no store app');
      await pumpScreen(tester);

      await tester.tap(find.text('업데이트하러 가기'));
      await tester.pump();

      expect(find.text(_failMessage), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('주소가 비어 있으면 열지 않고 안내만 띄운다', (tester) async {
      await pumpScreen(tester, storeUrl: '');

      await tester.tap(find.text('업데이트하러 가기'));
      await tester.pump();

      expect(launcher.opened, isEmpty);
      expect(find.text(_failMessage), findsOneWidget);
      await letToastGo(tester);
    });

    testWidgets('여는 중에 다시 눌러도 두 번 열지 않는다', (tester) async {
      launcher.hold = Completer<bool>();
      await pumpScreen(tester);

      await tester.tap(find.text('업데이트하러 가기'));
      await tester.tap(find.text('업데이트하러 가기'));
      await tester.pump();

      expect(launcher.opened, hasLength(1));
      launcher.hold!.complete(true);
      await tester.pump();
    });
  });

  group('뒤로가기', () {
    testWidgets('화면 안에서 뒤로가기를 막는다 (PopScope canPop: false)', (tester) async {
      await pumpScreen(tester);

      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    });
  });
}
