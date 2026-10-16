import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/consent/model/open_url.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/home/view/event_coming_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _title = '이벤트가 곧 열려요';
const _description = '새로운 이벤트가 준비되는 대로 여기서 알려 드릴게요. 인스타그램에서도 소식을 만나 보세요.';
const _buttonLabel = '인스타그램 보러 가기';
final _instagram = Uri.parse('https://www.instagram.com/campusmate_official');

/// 9b-1 이벤트(출시 예정, pen `q2mpPW`, 대장 전달 값 10-15).
void main() {
  late List<Uri> opened;
  late Future<bool> Function(Uri) open;

  setUp(() {
    opened = [];
    open = (uri) async {
      opened.add(uri);
      return true;
    };
  });

  /// 홈 위에 push 로 연다 — 앱바 뒤로가기로 홈에 돌아오는지 본다.
  Future<void> pump(WidgetTester tester, {Size size = const Size(360, 780), double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = GoRouter(
      initialLocation: AppRoutes.home,
      routes: [
        GoRoute(path: AppRoutes.home, builder: (context, state) => const Text('홈')),
        GoRoute(path: AppRoutes.events, builder: (context, state) => const EventComingScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [openExternalUrlProvider.overrideWithValue((uri) => open(uri))],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push(AppRoutes.events);
    await tester.pumpAndSettle();
  }

  Finder mascot() => find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/images/mascot-male-waiting.png',
      );
  Finder button() => find.ancestor(of: find.text(_buttonLabel), matching: find.byType(ElevatedButton));

  testWidgets('앱바 "이벤트" 18/700 · 뒤로 48 · 하단 내비 없음', (tester) async {
    await pump(tester);

    expect(find.text('이벤트'), findsOneWidget);
    expect(tester.widget<Text>(find.text('이벤트')).style, AppTypography.subNavTitle.copyWith(color: AppColors.ink));
    final back = find.byIcon(AppIcons.arrowLeft);
    expect(tester.widget<Icon>(back).size, 22);
    expect(tester.getSize(find.ancestor(of: back, matching: find.byType(IconButton))), const Size(48, 48));
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar, isNull);
  });

  testWidgets('마스코트 120 → 8 → 제목 20/700 → 8 → 설명 14/400 body lh1.55 → 16 → 버튼 312×52 · 가운데 · 아래 48 치우침', (tester) async {
    await pump(tester);

    final image = tester.getRect(mascot());
    final title = tester.getRect(find.text(_title));
    final description = tester.getRect(find.text(_description));
    final action = tester.getRect(button());
    expect(image.size, const Size(120, 120));
    expect(tester.widget<Image>(mascot()).fit, BoxFit.contain);
    expect(title.top, image.bottom + 8);
    expect(description.top, title.bottom + 8);
    expect(action.top, description.bottom + 16);
    expect(action.size, const Size(312, 52));
    expect(action.left, 24);
    expect(image.center.dx, 180);
    expect(tester.widget<Text>(find.text(_title)).textAlign, TextAlign.center);
    expect(tester.widget<Text>(find.text(_description)).textAlign, TextAlign.center);
    expect(
      tester.widget<Text>(find.text(_title)).style,
      AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
    );
    expect(tester.widget<Text>(find.text(_description)).style, AppTypography.bodySmall.copyWith(color: AppColors.body));
    // 본문 묶음이 앱바 아래 · 바닥 48 위 칸의 가운데다(03b 와 같은 규칙).
    final bodyCenter = (56 + (780 - 48)) / 2;
    expect((image.top + action.bottom) / 2, closeTo(bodyCenter, 0.5));
  });

  testWidgets('버튼 — #E5E5E5 · 모서리 14 · 인스타 로고 24 · 8 · 16/700 ink', (tester) async {
    await pump(tester);

    final style = tester.widget<ElevatedButton>(button()).style!;
    expect(style.backgroundColor!.resolve({}), AppColors.primaryDisabled);
    expect(style.shape!.resolve({}), RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)));
    final logo = find.descendant(of: button(), matching: find.byType(Image));
    expect(((tester.widget<Image>(logo).image) as AssetImage).assetName, 'assets/images/brand-instagram-v1.webp');
    expect(tester.getSize(logo), const Size(24, 24));
    expect(tester.getRect(find.text(_buttonLabel)).left, tester.getRect(logo).right + 8);
    expect(tester.widget<Text>(find.text(_buttonLabel)).style, AppTypography.button.copyWith(color: AppColors.ink));
  });

  testWidgets('버튼을 누르면 CampusMate 공식 인스타그램을 연다', (tester) async {
    await pump(tester);

    await tester.tap(button());
    await tester.pump();

    expect(opened, [_instagram]);
    expect(find.byType(AppToast), findsNothing);
  });

  testWidgets('열지 못하면(false · 예외) 실패 안내를 띄운다', (tester) async {
    for (final throws in [false, true]) {
      open = (uri) async {
        opened.add(uri);
        if (throws) throw StateError('기기 쪽 오류');
        return false;
      };
      await pump(tester);

      await tester.tap(button());
      await tester.pump();

      expect(find.text(const UnknownFailure().toDisplayMessage()), findsOneWidget, reason: 'throws=$throws');
      await tester.pump(const Duration(seconds: 3));
    }
    expect(opened, [_instagram, _instagram]);
  });

  testWidgets('앱바 뒤로가기로 홈에 돌아온다', (tester) async {
    await pump(tester);

    await tester.tap(find.byIcon(AppIcons.arrowLeft));
    await tester.pumpAndSettle();

    expect(find.text('홈'), findsOneWidget);
    expect(find.byType(EventComingScreen), findsNothing);
  });

  testWidgets('낭독기 — 마스코트는 읽지 않고, 버튼은 "인스타그램 보러 가기" 버튼으로 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(tester.widget<Image>(mascot()).excludeFromSemantics, isTrue);
    final data = tester.getSemantics(find.text(_buttonLabel)).getSemanticsData();
    expect(data.label, _buttonLabel);
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('작은 화면(320×568) · 글자 2배에서도 넘치지 않고 버튼까지 닿는다', (tester) async {
    await pump(tester, size: const Size(320, 568), textScale: 2);

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(button(), 100, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });
}
