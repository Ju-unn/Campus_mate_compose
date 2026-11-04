import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/common/widgets/app_lottie_view.dart';
import 'package:campus_mate/core/theme/app_lottie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

/// 시험용 장면: 30fps · 프레임 0~100(3.33초), intro 0~10(0.33초), loop 10~100. 그림 · 층 없음.
const _withMarkers =
    '{"v":"5.7.14","fr":30,"ip":0,"op":100,"w":10,"h":10,"assets":[],"layers":[],'
    '"markers":[{"tm":0,"cm":"intro","dr":10},{"tm":10,"cm":"loop","dr":90}]}';

/// 표시(marker)가 없는 장면 — 처음부터 끝까지가 반복 구간이다.
const _withoutMarkers = '{"v":"5.7.14","fr":30,"ip":0,"op":100,"w":10,"h":10,"assets":[],"layers":[]}';

const _scene = LottieScene(path: 'test/with_markers.json', stillFrame: 50);
const _plainScene = LottieScene(path: 'test/without_markers.json', stillFrame: 0);
const _missingScene = LottieScene(path: 'test/missing.json', stillFrame: 0);

/// 메모리에서 json 을 내주는 번들 — 없는 경로는 실제 번들처럼 읽기 오류를 낸다.
class _MemoryBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final text = switch (key) {
      'test/with_markers.json' => _withMarkers,
      'test/without_markers.json' => _withoutMarkers,
      _ => throw FlutterError('Unable to load asset: "$key".'),
    };
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

Widget _app(Widget child, {bool disableAnimations = false}) {
  return DefaultAssetBundle(
    bundle: _MemoryBundle(),
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(textDirection: TextDirection.ltr, child: Center(child: child)),
    ),
  );
}

/// 파일 읽기 · onLoaded 까지 흘려보낸다(모두 마이크로태스크라 가짜 시계로 충분하다).
Future<void> _load(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _pumpView(
  WidgetTester tester,
  AppLottieView view, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(_app(view, disableAnimations: disableAnimations));
  await _load(tester);
}

AnimationController _controller(WidgetTester tester) =>
    tester.widget<LottieBuilder>(find.byType(LottieBuilder)).controller! as AnimationController;

void main() {
  setUp(() => Lottie.cache.clear());

  // lottie 는 끝 프레임을 `op - 0.01` 로 읽어 진행 값이 프레임/(op-0.01) 이다 — 50/100 프레임은 0.5 에서 0.1 프레임 안쪽으로 본다.
  group('동작 줄이기', () {
    testWidgets('켜져 있으면 움직이지 않고 장면에 정한 멈춤 프레임(50/100)에 서 있다', (tester) async {
      await _pumpView(tester, const AppLottieView(scene: _scene), disableAnimations: true);

      final controller = _controller(tester);
      expect(controller.value, closeTo(0.5, 1e-3));
      expect(controller.isAnimating, isFalse);
      await tester.pump(const Duration(seconds: 5));
      expect(controller.value, closeTo(0.5, 1e-3));
    });

    testWidgets('실행 중에 켜면 그 자리에서 멈춤 프레임으로 서고, 끄면 다시 움직인다', (tester) async {
      await _pumpView(tester, const AppLottieView(scene: _scene));
      expect(_controller(tester).isAnimating, isTrue);

      await tester.pumpWidget(_app(const AppLottieView(scene: _scene), disableAnimations: true));
      await tester.pump();
      expect(_controller(tester).isAnimating, isFalse);
      expect(_controller(tester).value, closeTo(0.5, 1e-3));

      await tester.pumpWidget(_app(const AppLottieView(scene: _scene)));
      await tester.pump();
      expect(_controller(tester).isAnimating, isTrue);
    });
  });

  group('재생 방식', () {
    testWidgets('기본: 처음 구간(intro)을 한 번 재생하고, 그 뒤로는 반복 구간(loop)만 되풀이한다', (tester) async {
      await _pumpView(tester, const AppLottieView(scene: _scene));
      final controller = _controller(tester);

      expect(controller.isAnimating, isTrue);
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.value, lessThan(0.1), reason: 'intro(0~10프레임, 0.33초) 안');

      // 반복 구간 한 바퀴(90프레임 = 3초)를 두 번 넘게 돌려 보며, 한 번도 intro 로 돌아가지 않는지 본다.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (i < 2) continue; // intro 가 끝나는 0.33초 뒤부터
        expect(controller.value, greaterThanOrEqualTo(0.1 - 1e-9), reason: '${(i + 1) * 250}ms');
        expect(controller.value, lessThanOrEqualTo(1.0));
      }
    });

    testWidgets('처음부터 반복: intro 를 따로 두지 않고 0 부터 끝까지 돌고 다시 0 으로 돌아온다', (tester) async {
      await _pumpView(tester, const AppLottieView(scene: _scene, playback: AppLottiePlayback.wholeLoop));
      final controller = _controller(tester);

      await tester.pump(const Duration(milliseconds: 3000));
      expect(controller.value, greaterThan(0.85));
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.value, lessThan(0.2), reason: '한 바퀴(3.33초)가 지나 처음으로 돌아왔다');
    });

    testWidgets('표시(marker)가 없는 장면은 기본 방식이어도 처음부터 반복한다', (tester) async {
      await _pumpView(tester, const AppLottieView(scene: _plainScene));
      final controller = _controller(tester);

      await tester.pump(const Duration(milliseconds: 3000));
      expect(controller.value, greaterThan(0.85));
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.value, lessThan(0.2));
    });
  });

  group('파일을 못 읽을 때', () {
    testWidgets('예외 없이 빈 상자(받은 크기)를 남긴다', (tester) async {
      await _pumpView(tester, const AppLottieView(scene: _missingScene, width: 40, height: 30));

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(AppLottieView)), const Size(40, 30));
      expect(find.byType(LottieBuilder), findsOneWidget);
    });

    testWidgets('대체 위젯을 받았으면 그것을 보인다', (tester) async {
      await _pumpView(
        tester,
        const AppLottieView(scene: _missingScene, width: 40, height: 30, fallback: Text('대체')),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('대체'), findsOneWidget);
    });
  });

  group('크기 · 맞춤 · 접근성', () {
    testWidgets('크기와 맞춤(BoxFit)을 그대로 lottie 에 넘긴다', (tester) async {
      await _pumpView(
        tester,
        const AppLottieView(scene: _scene, width: 300, height: 250, fit: BoxFit.cover),
      );

      final lottie = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
      expect((lottie.width, lottie.height, lottie.fit), (300.0, 250.0, BoxFit.cover));
      expect(tester.getSize(find.byType(AppLottieView)), const Size(300, 250));
    });

    testWidgets('라벨을 주지 않으면 장식이라 낭독기에서 뺀다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpView(tester, const AppLottieView(scene: _scene, width: 40, height: 30));

      expect(
        find.descendant(of: find.byType(AppLottieView), matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );
      expect(tester.getSemantics(find.byType(AppLottieView)).label, isEmpty);
      handle.dispose();
    });

    testWidgets('라벨을 주면 그 라벨 하나로 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpView(tester, const AppLottieView(scene: _scene, width: 40, height: 30, semanticLabel: '캠퍼스메이트'));

      expect(find.bySemanticsLabel('캠퍼스메이트'), findsOneWidget);
      handle.dispose();
    });
  });

  test('lib 에서 lottie 를 부르는 곳은 app_lottie_view.dart 하나뿐이다', () {
    const allowed = 'lib/common/widgets/app_lottie_view.dart';
    final forbidden = RegExp(r'Lottie\.asset\(|Lottie\.network\(|LottieBuilder|package:lottie/');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      final path = entity.path.replaceAll(r'\', '/');
      if (entity is! File || !path.endsWith('.dart') || path == allowed) continue;
      if (forbidden.hasMatch(entity.readAsStringSync())) offenders.add(path);
    }

    expect(offenders, isEmpty, reason: '화면은 AppLottieView 로만 움직이는 그림을 쓴다');
    expect(File(allowed).readAsStringSync(), contains('Lottie.asset('));
  });
}
