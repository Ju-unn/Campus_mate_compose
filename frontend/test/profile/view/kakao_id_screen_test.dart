import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/profile/model/kakao_id_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/view/kakao_id_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_kakao_id_repository.dart';
import '../model/fake_onboarding_repository.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        kakaoIdRepositoryProvider.overrideWithValue(FakeKakaoIdRepository()),
        onboardingRepositoryProvider.overrideWithValue(FakeOnboardingRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: KakaoIdScreen()),
      ),
    );
  }

  testWidgets('카카오톡 설정 화면 예시를 캡션과 함께 보여준다(pen W2tFQt)', (tester) async {
    await pump(tester);

    expect(find.text('카카오톡 설정 화면 예시'), findsOneWidget);
    expect(find.text('ID 검색 허용'), findsOneWidget);
    expect(find.text('카카오톡 > 설정 > 프로필 관리 > 카카오톡 ID 에서 켤 수 있어요'), findsOneWidget);
  });

  testWidgets('그림이라 탭에 반응하지 않고 한 문장으로 읽힌다', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    final node = tester.getSemantics(find.text('ID 검색 허용'));
    expect(node.label, '카카오톡 설정 예시, ID 검색 허용 켜짐');
    // 켜고 끄는 건 카카오톡에서 한다 — 여기엔 누를 것이 없다.
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(find.byType(Switch), findsNothing);

    await tester.tap(find.byIcon(AppIcons.check), warnIfMissed: false);
    await tester.pump();

    expect(find.text('ID 검색 허용'), findsOneWidget);

    semantics.dispose();
  });
}
