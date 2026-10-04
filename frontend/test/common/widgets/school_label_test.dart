import 'dart:async';
import 'dart:io';

import 'package:campus_mate/common/university_logos.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// 로고 요청을 받기만 하고 답하지 않는 HttpClient — 로고는 "아직 오는 중"이라 자리만 잡는다.
class _PendingHttpClient extends Mock implements HttpClient {}

/// 로고 요청마다 연결 오류를 내는 HttpClient — 로고를 못 불러온 경우.
class _FailingHttpClient extends Mock implements HttpClient {}

/// 학교 이름은 지어낸 값이다.
const _school = '가나대학교';
const _url = 'https://logo.test/gana.webp';

final _logo = find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage);
final _logoPicture = find.descendant(of: _logo, matching: find.byType(RawImage));

void main() {
  setUpAll(() => registerFallbackValue(Uri()));

  Future<void> pump(
    WidgetTester tester,
    SchoolLabel label, {
    Map<String, String> logos = const {_school: _url},
    HttpClient? client,
  }) async {
    final pending = _PendingHttpClient();
    when(() => pending.getUrl(any())).thenAnswer((_) => Completer<HttpClientRequest>().future);
    debugNetworkImageHttpClientProvider = () => client ?? pending;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [universityLogosProvider.overrideWith((ref) => logos)],
        child: MaterialApp(
          home: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 200, child: label)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // 그림 캐시가 앞 테스트의 로고를 쥐고 있지 않게 비우고, 디버그 훅은 테스트 본문 끝에서 되돌린다(불변식 검사가 tearDown 보다 먼저다).
  setUp(() => PaintingBinding.instance.imageCache.clear());

  for (final (text, logo) in [(12.0, 14.0), (14.0, 16.0), (16.0, 18.0)]) {
    testWidgets('글자 $text 이면 로고 $logo, 글자는 로고 오른쪽 4(02_SCHOOL_ROW_HEIGHT_FIX)', (tester) async {
      await pump(tester, SchoolLabel(_school, style: TextStyle(fontSize: text, height: 1.5)));

      expect(tester.getSize(_logoPicture), Size(logo, logo));
      expect(tester.getTopLeft(find.text(_school)).dx - tester.getTopRight(_logoPicture).dx, 4);
      debugNetworkImageHttpClientProvider = null;
    });
  }

  testWidgets('한 줄이면 로고는 줄 가운데', (tester) async {
    await pump(tester, const SchoolLabel(_school, style: TextStyle(fontSize: 14, height: 1.5)));

    expect(tester.getCenter(_logoPicture).dy, tester.getCenter(find.text(_school)).dy);
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('두 줄로 넘어가면 로고는 첫 줄 가운데 — 두 줄 덩어리 가운데로 옮기지 않는다', (tester) async {
    const text = '$_school · 아주아주긴학과이름';
    await pump(tester, const SchoolLabel(_school, text: text, style: TextStyle(fontSize: 14, height: 1.5)));

    final textRect = tester.getRect(find.text(text));
    expect(textRect.height, 42, reason: '폭 200 에서 두 줄이어야 이 테스트가 뜻이 있다');
    expect(tester.getCenter(_logoPicture).dy, textRect.top + 21 / 2);
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('글자를 키우면 로고는 그대로, 커진 첫 줄 가운데', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, const SchoolLabel(_school, style: TextStyle(fontSize: 14, height: 1.5)));

    expect(tester.getSize(_logoPicture), const Size(16, 16));
    expect(tester.getCenter(_logoPicture).dy, tester.getTopLeft(find.text(_school)).dy + 42 / 2);
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('로고가 없는 학교는 간격 없이 이름만', (tester) async {
    await pump(tester, const SchoolLabel(_school, style: TextStyle(fontSize: 14, height: 1.5)), logos: const {});

    expect(_logo, findsNothing);
    expect(tester.getTopLeft(find.text(_school)).dx, 0);
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('로고를 못 불러오면 간격까지 빼고 이름만', (tester) async {
    final client = _FailingHttpClient();
    when(() => client.getUrl(any())).thenAnswer((_) async => throw const SocketException('없음'));
    await pump(tester, const SchoolLabel(_school, style: TextStyle(fontSize: 14, height: 1.5)), client: client);
    await tester.pump();

    expect(_logoPicture, findsNothing);
    expect(tester.getTopLeft(find.text(_school)).dx, 0);
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('textAlign end 로 두 줄이면 두 줄 다 칸 오른쪽 끝, 로고는 첫 줄 바로 앞 4', (tester) async {
    const text = '$_school · 아주아주긴학과이름';
    await pump(
      tester,
      const SchoolLabel(_school, text: text, textAlign: TextAlign.end, style: TextStyle(fontSize: 14, height: 1.5)),
    );

    final p = tester.renderObject<RenderParagraph>(find.text(text));
    final lines = <double, List<TextBox>>{};
    for (final box in p.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: text.length))) {
      lines.putIfAbsent(box.top, () => []).add(box);
    }
    expect(lines, hasLength(2), reason: '폭 200 에서 두 줄이어야 이 테스트가 뜻이 있다');
    for (final line in lines.values) {
      expect(p.localToGlobal(Offset(line.last.right, 0)).dx, closeTo(200, 0.5));
    }
    final firstLineLeft = p.localToGlobal(Offset(lines.values.first.first.left, 0)).dx;
    expect(firstLineLeft - tester.getTopRight(_logoPicture).dx, closeTo(4, 0.5));
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('로고는 낭독기에 읽히지 않는다 — 이름이 글자로 있다', (tester) async {
    await pump(tester, const SchoolLabel(_school, style: TextStyle(fontSize: 14, height: 1.5)));

    expect(tester.widget<Image>(_logo).excludeFromSemantics, isTrue);
    debugNetworkImageHttpClientProvider = null;
  });
}
