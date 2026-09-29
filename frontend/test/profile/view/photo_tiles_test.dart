import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 빈 "사진 추가" 칸(`AddPhotoTile`) — 글자가 칸에 안 들어가면 더하기 아이콘만 보인다(대장 결정 (가), 2026-09-29).
/// 15e 보조 칸 66×88 은 글자를 키우면 좁고, 04-2 칸(폭 360 에서 158×158)은 넉넉하다.
void main() {
  Future<void> pumpTile(WidgetTester tester, {required Size size, required double scale}) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox.fromSize(size: size, child: AddPhotoTile(onTap: () async {}))),
        ),
      ),
    );
  }

  const smallCell = Size(66, 88);
  const wideCell = Size(158, 158);

  for (final scale in [1.0, 1.3, 1.5]) {
    testWidgets('66×88 칸 · 배율 $scale — 아이콘과 "사진 추가" 글자가 다 보인다', (tester) async {
      await pumpTile(tester, size: smallCell, scale: scale);

      expect(tester.takeException(), isNull);
      expect(find.byIcon(AppIcons.plus), findsOneWidget);
      expect(find.text('사진 추가'), findsOneWidget);
    });
  }

  testWidgets('66×88 칸 · 배율 2.0 — 글자는 숨기고 아이콘만, 넘치지 않는다, 낭독 이름은 "사진 추가" 그대로', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTile(tester, size: smallCell, scale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('사진 추가'), findsNothing);
    expect(find.byIcon(AppIcons.plus), findsOneWidget);
    expect(tester.getSemantics(find.byType(InkWell)), isSemantics(label: '사진 추가', hasTapAction: true));
    semantics.dispose();
  });

  testWidgets('글자가 보일 때도 낭독 이름은 "사진 추가" 하나다 — 아이콘만 둘 때와 같은 모양', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTile(tester, size: smallCell, scale: 1.0);

    expect(tester.getSemantics(find.byType(InkWell)), isSemantics(label: '사진 추가', hasTapAction: true));
    semantics.dispose();
  });

  testWidgets('04-2 넓은 칸(158×158)은 배율 2.0 에서도 글자가 보인다', (tester) async {
    await pumpTile(tester, size: wideCell, scale: 2.0);

    expect(tester.takeException(), isNull);
    expect(find.text('사진 추가'), findsOneWidget);
    expect(find.byIcon(AppIcons.plus), findsOneWidget);
  });
}
