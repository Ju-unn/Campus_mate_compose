import 'package:campus_mate/chat/view/swipe_to_leave.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int leaves;
  late int taps;

  setUp(() {
    leaves = 0;
    taps = 0;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            SwipeToLeave(
              onLeave: () async => leaves += 1,
              child: Material(
                color: AppColors.canvas,
                child: InkWell(
                  onTap: () => taps += 1,
                  child: const SizedBox(height: 72, width: double.infinity, child: Text('여우비')),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Finder action() => find.ancestor(of: find.text('나가기'), matching: find.byType(Material)).first;

  testWidgets('왼쪽으로 밀면 80 에서 멈추고 오른쪽 80 에 빨간 "나가기"(pen zMfIn · O0ULe2)', (tester) async {
    await pump(tester);

    await tester.drag(find.text('여우비'), const Offset(-200, 0));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('여우비')).dx, -80);
    final rect = tester.getRect(action());
    expect((rect.left, rect.width, rect.height), (280, 80, 72));
    final material = tester.widget<Material>(action());
    expect((material.color, material.borderRadius), (AppColors.primary, null));
    final label = tester.widget<Text>(find.text('나가기')).style!;
    expect((label.fontSize, label.fontWeight, label.color), (14, FontWeight.w700, AppColors.onPrimary));
  });

  testWidgets('조금만 밀면 제자리로 돌아온다', (tester) async {
    await pump(tester);

    await tester.drag(find.text('여우비'), const Offset(-20, 0));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('여우비')).dx, 0);
  });

  testWidgets('절반(40)을 넘겨 밀어야 열린다', (tester) async {
    await pump(tester);

    // 손가락 거리에서 끌기 시작 문턱(18)을 뺀 만큼 밀린다 — -50 은 32(0.4), -70 은 52(0.65).
    await tester.drag(find.text('여우비'), const Offset(-50, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('여우비')).dx, 0);

    await tester.drag(find.text('여우비'), const Offset(-70, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('여우비')).dx, -80);
  });

  testWidgets('열린 줄을 오른쪽으로 빠르게 밀면 닫힌다', (tester) async {
    await pump(tester);
    await tester.drag(find.text('여우비'), const Offset(-200, 0));
    await tester.pumpAndSettle();

    // 짧은 플링은 테스트 하네스가 속도 0 으로 재서 큰 값을 쓴다.
    await tester.fling(find.text('여우비'), const Offset(150, 0), 3000);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('여우비')).dx, 0);
  });

  testWidgets('"나가기" 를 누르면 줄이 닫히고 onLeave 를 부른다', (tester) async {
    await pump(tester);
    await tester.drag(find.text('여우비'), const Offset(-200, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('나가기'));
    await tester.pumpAndSettle();

    expect(leaves, 1);
    expect(tester.getTopLeft(find.text('여우비')).dx, 0);
  });

  testWidgets('열린 줄을 누르면 닫히기만 하고 방으로 가지 않는다', (tester) async {
    await pump(tester);
    await tester.drag(find.text('여우비'), const Offset(-200, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('여우비'));
    await tester.pumpAndSettle();

    expect((taps, leaves), (0, 0));
    expect(tester.getTopLeft(find.text('여우비')).dx, 0);
  });

  testWidgets('밀지 못하는 낭독기에는 "채팅방 나가기" 동작으로 준다', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final node = tester.getSemantics(find.byType(SwipeToLeave));
    final id = CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: '채팅방 나가기'));
    expect(node.getSemanticsData().customSemanticsActionIds, contains(id));
    node.owner!.performAction(node.id, SemanticsAction.customAction, id);
    await tester.pumpAndSettle();

    expect(leaves, 1);
    handle.dispose();
  });
}
