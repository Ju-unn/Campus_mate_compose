import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/view/ideal_conditions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../profile/model/fake_ideal_conditions_repository.dart';
import '../../profile/model/fake_onboarding_repository.dart';
import '../model/fake_me_repository.dart';

MyProfile _profile({int? ageMin = 25, int? ageMax = 30, int? heightMin = 160, int? heightMax = 175}) => MyProfile(
      nickname: '여우',
      age: 23,
      university: '가나대학교',
      major: null,
      heightCm: null,
      mbti: null,
      avatarUrl: null,
      preferredAgeMin: ageMin,
      preferredAgeMax: ageMax,
      preferredHeightMin: heightMin,
      preferredHeightMax: heightMax,
      bio: '안녕하세요',
      preferredMbtiFlags: const {'E': true},
      preferredAnimalTypes: const [AnimalType.dog],
      preferredImpressionTypes: const [ImpressionType.kind],
    );

/// 06-1 편집 모드(`/me/ideal-conditions`, 계획서 A5 · D5). 화면 15 의 선호 나이 · 키 행에서 연다.
void main() {
  late FakeMeRepository me;
  late FakeIdealConditionsRepository conditions;
  late FakeOnboardingRepository onboarding;

  Future<void> pump(WidgetTester tester, {MyProfile? profile}) async {
    me = FakeMeRepository(Success(profile ?? _profile()));
    conditions = FakeIdealConditionsRepository();
    onboarding = FakeOnboardingRepository();
    final container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(me),
        idealConditionsRepositoryProvider.overrideWithValue(conditions),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        // 화면 15 처럼 내 프로필을 보고 있다 — 편집이 invalidate 하면 이 화면이 다시 읽는다.
        GoRoute(
          path: '/',
          builder: (context, state) => Consumer(
            builder: (context, ref, _) {
              ref.watch(myProfileProvider);
              return Scaffold(
                body: TextButton(onPressed: () => context.push('/edit'), child: const Text('화면 15')),
              );
            },
          ),
        ),
        GoRoute(path: '/edit', builder: (context, state) => const IdealConditionsScreen(isEditing: true)),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
      ),
    );
    await container.read(myProfileProvider.future);
    await tester.pump();
    await openEditor(tester);
  }

  AppButton saveButton(WidgetTester tester) => tester.widget<AppButton>(find.byType(AppButton));

  List<bool?> ignoreChecks(WidgetTester tester) =>
      [for (final box in tester.widgetList<Checkbox>(find.byType(Checkbox))) box.value];

  testWidgets('앱바는 편집 앱바 "이상형 조건 수정"(D5), 진행 점 없음, 버튼은 "저장", 본문 헤드라인은 그대로', (tester) async {
    await pump(tester);

    expect(tester.widget<EditAppBar>(find.byType(EditAppBar)).title, '이상형 조건 수정');
    expect(find.byType(OnboardingAppBar), findsNothing);
    expect(saveButton(tester).label, '저장');
    expect(find.text('어떤 사람이 좋아요?'), findsOneWidget);
  });

  testWidgets('서버 값이 나이 · 키 요약에 그대로 나온다', (tester) async {
    await pump(tester);

    expect(find.text('25세 ~ 30세'), findsOneWidget);
    expect(find.text('160cm ~ 175cm'), findsOneWidget);
    expect(ignoreChecks(tester), [false, false]);
  });

  testWidgets('"상관없어요" 두 경우(나이 전 구간 · 키 없음)는 체크된 채 열린다', (tester) async {
    await pump(tester, profile: _profile(ageMin: 19, ageMax: 35, heightMin: null, heightMax: null));

    expect(ignoreChecks(tester), [true, true]);
  });

  testWidgets('저장하면 앞 화면으로 돌아가고 화면 15 가 다시 읽는다 — 온보딩 단계는 조회하지 않는다', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();

    expect(conditions.submitted!.preferredAgeMin, 25);
    expect(find.text('화면 15'), findsOneWidget);
    expect(find.byType(IdealConditionsScreen), findsNothing);
    expect(me.calls, 2);
    expect(onboarding.fetchCount, 0);
  });

  testWidgets('저장 중에는 버튼이 흰 스피너로 바뀐다(D8)', (tester) async {
    await pump(tester);
    conditions.hold = Completer<void>();

    await tester.tap(find.byType(AppButton));
    await tester.pump();

    expect(saveButton(tester).isLoading, isTrue);
    conditions.hold!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('저장이 실패하면 버튼 위 오류 글을 보이고 그 자리에 남는다', (tester) async {
    await pump(tester);
    conditions.nextResult = const FailureResult(NetworkFailure());

    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();

    final error = find.text(const NetworkFailure().toDisplayMessage());
    expect(error, findsOneWidget);
    expect(tester.getBottomLeft(error).dy, lessThan(tester.getTopLeft(find.byType(AppButton)).dy));
    expect(find.byType(IdealConditionsScreen), findsOneWidget);
  });

  testWidgets('ideal_conditions_edit_is_filled_from_the_server_each_time_it_opens — 저장 없이 나갔다 다시 열면 서버 값(Review Focus 5)', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.text('키는 상관없어요'));
    await tester.tap(find.text('키는 상관없어요'));
    await tester.pump();
    expect(ignoreChecks(tester), [false, true]);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await openEditor(tester);

    expect(ignoreChecks(tester), [false, false]);
    expect(conditions.submitted, isNull);
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0). 편집 모드가 더한 것(앱바 제목 · 저장 버튼)은 네 배율 모두에서 본다.
  // 본문은 온보딩 06-1 그대로라 main(b3f7a25)에서도 배율 1.3 부터 얼굴상 칸(`appearance_pickers.dart` 33줄)이 8px
  // 넘치고 얼굴상 이름 · MBTI 글자 · 캡션 두 줄이 잘린다 — 허락 표 밖 파일이라 이 PR 에서 고치지 않았다(보고서 "결정 필요").
  // 그래서 본문까지 깨끗한지는 배율 1.0 에서만 단정한다.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('06-1 편집 — 폭 360 · 글자 배율 $scale 에서 편집 앱바 제목 · 저장 버튼이 넘치거나 잘리지 않는다(스크롤 전 · 끝)', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(tester);
      final bodyErrors = [tester.takeException()];
      final clipped = _clippedTexts();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      bodyErrors.add(tester.takeException());
      clipped.addAll(_clippedTexts());

      expect(clipped, isNot(contains('이상형 조건 수정')));
      expect(clipped, isNot(contains('저장')));
      expect(find.text('이상형 조건 수정'), findsOneWidget);
      if (scale == 1.0) {
        expect(bodyErrors, everyElement(isNull));
        expect(clipped, isEmpty);
      }
    });
  }
}

Future<void> openEditor(WidgetTester tester) async {
  await tester.tap(find.text('화면 15'));
  await tester.pumpAndSettle();
}

/// 고정 상자에 갇혀 오류 없이 잘린 글자. 폭은 배치 때 받은 최대 폭으로 잰다(화면 15 테스트와 같은 방식).
List<String> _clippedTexts() => [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.getMaxIntrinsicHeight(p.constraints.maxWidth) > p.size.height + 0.5 ||
                p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
          p.text.toPlainText(),
    ];
