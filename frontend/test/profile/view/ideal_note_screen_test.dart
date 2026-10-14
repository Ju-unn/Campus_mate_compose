import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/profile/model/ideal_note_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/view/ideal_note_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_ideal_note_repository.dart';
import '../model/fake_onboarding_repository.dart';

// 06-2a 두 상태(pen vMxds 쓰는 중 · fGKgO "다음" 뒤 오류). 2026-09-27 사용자 "나".
void main() {
  late FakeIdealNoteRepository repository;

  Future<void> pump(WidgetTester tester) async {
    repository = FakeIdealNoteRepository();
    final container = ProviderContainer(
      overrides: [
        idealNoteRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: IdealNoteScreen()),
      ),
    );
  }

  Finder hint() => find.text('10자 이상 입력해 주세요');

  testWidgets('처음엔 안내가 없고 "다음"은 눌린다', (tester) async {
    await pump(tester);

    expect(hint(), findsNothing);
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
  });

  testWidgets('10자 전엔 회색 안내, "다음"을 누르면 저장 없이 빨간 오류, 다시 쓰면 회색으로 돌아간다', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '말이잘통하는');
    await tester.pump();
    expect(hint(), findsOneWidget);
    expect(find.byIcon(AppIcons.circleAlert), findsNothing);

    await tester.tap(find.text('다음'));
    await tester.pump();
    expect(repository.submittedNote, isNull);
    expect(hint(), findsOneWidget);
    expect(find.byIcon(AppIcons.circleAlert), findsOneWidget);

    await tester.enterText(find.byType(TextField), '말이잘통하는사');
    await tester.pump();
    expect(hint(), findsOneWidget);
    expect(find.byIcon(AppIcons.circleAlert), findsNothing);
  });

  String fieldText(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText)).controller.text;

  // 2026-10-14 사용자 결정 "추천대로": 화면 상한 300자(서버는 1000 그대로), 엔터 줄은 칸 maxLines 와 같은 6줄.
  testWidgets('300자(코드포인트)까지만 들어간다 — 카운터는 없다(pen dIONW)', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '가' * 301);
    await tester.pump();

    expect(fieldText(tester).runes.length, 300);
    expect(find.textContaining('/ 300'), findsNothing);
  });

  testWidgets('엔터 줄은 6줄까지 — 붙여 넣은 넘는 줄 바꿈은 공백이 된다', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), '1\n2\n3\n4\n5\n6\n7');
    await tester.pump();

    expect(fieldText(tester), '1\n2\n3\n4\n5\n6 7');
  });
}
