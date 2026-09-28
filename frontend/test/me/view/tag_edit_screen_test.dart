import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/onboarding_app_bar.dart';
import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/tag_picker_repository_provider.dart';
import 'package:campus_mate/profile/view/tag_picker_screen.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../profile/model/fake_onboarding_repository.dart';
import '../../profile/model/fake_tag_picker_repository.dart';
import '../model/fake_me_repository.dart';

const _profile = MyProfile(
  nickname: '여우',
  age: 23,
  university: '가나대학교',
  major: null,
  heightCm: null,
  mbti: null,
  avatarUrl: null,
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: null,
  preferredHeightMax: null,
  bio: '안녕하세요',
  interestTags: ['카페가기', '여행', '요리'],
  myTraits: ['유머러스', '성실한', '차분한'],
  idealTraits: ['솔직한', '연락 잘하는', '다정한'],
);

/// 편집 모드 태그 화면(04-5 · 04-6 · 06-2 를 `/me/edit/tags/:kind` 에 다시 띄운 것, 계획서 A3 · D5 · T5).
void main() {
  late FakeMeRepository me;
  late FakeTagPickerRepository tags;
  late FakeOnboardingRepository onboarding;

  /// 앞 화면(15c 자리) 위에 편집 화면을 올린다 — 저장하면 앞 화면으로 돌아와야 한다.
  Future<void> pump(WidgetTester tester, {TagPickerKind kind = TagPickerKind.interests}) async {
    me = FakeMeRepository(const Success(_profile));
    tags = FakeTagPickerRepository();
    onboarding = FakeOnboardingRepository();
    final container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(me),
        tagPickerRepositoryProvider.overrideWithValue(tags),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        // 15c 처럼 내 프로필을 보고 있다 — 편집이 invalidate 하면 이 화면이 다시 읽는다.
        GoRoute(
          path: '/',
          builder: (context, state) => Consumer(
            builder: (context, ref, _) {
              ref.watch(myProfileProvider);
              return Scaffold(
                body: TextButton(onPressed: () => context.push('/tags'), child: const Text('앞 화면')),
              );
            },
          ),
        ),
        GoRoute(path: '/tags', builder: (context, state) => TagPickerScreen(kind: kind, isEditing: true)),
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
    await openEditor(tester);
  }

  bool isSelected(WidgetTester tester, String tag) =>
      tester.widget<SelectChip>(find.widgetWithText(SelectChip, tag)).isSelected;

  AppButton saveButton(WidgetTester tester) => tester.widget<AppButton>(find.byType(AppButton));

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byType(AppButton));
    await tester.pump();
  }

  for (final (kind, title) in [
    (TagPickerKind.interests, '관심사 수정'),
    (TagPickerKind.myTraits, '나의 특징 수정'),
    (TagPickerKind.idealTraits, '이상형 특징 수정'),
  ]) {
    testWidgets('${kind.name} — 앱바는 편집 앱바 "$title"(D5), 진행 점 없음, 본문 헤드라인 · 안내는 온보딩 그대로', (tester) async {
      await pump(tester, kind: kind);

      expect(tester.widget<EditAppBar>(find.byType(EditAppBar)).title, title);
      expect(find.byType(OnboardingAppBar), findsNothing);
      expect(find.text(kind.headline), findsOneWidget);
      expect(find.text(kind.subtext), findsOneWidget);
    });
  }

  testWidgets('버튼은 "다음" 이 아니라 "저장"(DESIGN 15c)', (tester) async {
    await pump(tester);

    expect(saveButton(tester).label, '저장');
    expect(find.text('다음'), findsNothing);
  });

  testWidgets('열면 서버의 태그가 켜져 있다', (tester) async {
    await pump(tester, kind: TagPickerKind.myTraits);

    for (final tag in _profile.myTraits) {
      expect(isSelected(tester, tag), isTrue, reason: tag);
    }
    expect(find.text('3/5개 선택'), findsOneWidget);
  });

  testWidgets('3개 미만이면 "저장" 이 꺼진다', (tester) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(SelectChip, '카페가기'));
    await tester.pump();

    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('저장하면 같은 endpoint 로 보내고 앞 화면으로 돌아간다 — 온보딩 단계는 조회하지 않는다', (tester) async {
    await pump(tester, kind: TagPickerKind.idealTraits);
    await tester.tap(find.widgetWithText(SelectChip, '다정한'));
    await tester.pump();
    await tester.tap(find.widgetWithText(SelectChip, '긍정적인'));
    await tester.pump();

    await tapSave(tester);
    await tester.pumpAndSettle();

    expect(tags.submittedEndpoint, 'ideal-traits');
    expect(tags.submittedTags!.toSet(), {'솔직한', '연락 잘하는', '긍정적인'});
    expect(find.text('앞 화면'), findsOneWidget);
    expect(find.byType(TagPickerScreen), findsNothing);
    expect(me.calls, 2, reason: '화면 15 · 15c 가 새 태그를 그리도록 다시 읽는다');
    expect(onboarding.fetchCount, 0);
  });

  testWidgets('저장 중에는 버튼이 스피너로 바뀐다(D8)', (tester) async {
    await pump(tester);
    tags.hold = Completer<void>();

    await tapSave(tester);

    expect(saveButton(tester).isLoading, isTrue);
    expect(find.descendant(of: find.byType(AppButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    tags.hold!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('저장이 실패하면 버튼 위 오류 글을 보이고 그 자리에 남는다', (tester) async {
    await pump(tester);
    tags.nextResult = const FailureResult(NetworkFailure());

    await tapSave(tester);
    await tester.pumpAndSettle();

    final error = find.text(const NetworkFailure().toDisplayMessage());
    expect(error, findsOneWidget);
    expect(tester.getBottomLeft(error).dy, lessThan(tester.getTopLeft(find.byType(AppButton)).dy));
    expect(find.byType(TagPickerScreen), findsOneWidget);
  });

  testWidgets('tag_edit_is_filled_from_the_server_each_time_it_opens — 저장 없이 나갔다 다시 열면 서버 값(Review Focus 5)', (tester) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(SelectChip, '카페가기'));
    await tester.pump();
    expect(isSelected(tester, '카페가기'), isFalse);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await openEditor(tester);

    expect(isSelected(tester, '카페가기'), isTrue);
    expect(tags.submittedTags, isNull);
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 넘치거나 잘리지 않는다. 화면 15 테스트와 같은 잣대.
  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('편집 모드 태그 화면 — 폭 360 · 글자 배율 $scale 에서 넘침 · 잘림이 없다', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pump(tester, kind: TagPickerKind.idealTraits);

      expect(tester.takeException(), isNull);
      expect(_clippedTexts(), isEmpty);
    });
  }
}

Future<void> openEditor(WidgetTester tester) async {
  await tester.tap(find.text('앞 화면'));
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
