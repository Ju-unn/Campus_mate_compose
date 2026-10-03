import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/router/app_routes.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/view/basic_info_edit_screen.dart';
import 'package:campus_mate/me/view/edit_app_bar.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/model/basic_info_repository_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../profile/model/fake_basic_info_repository.dart';
import '../model/fake_me_repository.dart';

/// 잠금이 풀리는 때 — 한국 시각 10월 27일 0시(계획서 A7 예).
/// 한국 시간대 PC 에서는 `toLocal()` 로 바꿔도 이 테스트가 통과한다 — 잡는 곳은 UTC 로 도는 CI 다(검토 사소 3).
final _unlocksAt = DateTime.parse('2026-10-26T15:00:00+00:00');

/// 이름·학교는 지어낸 값이다.
MyProfile _profile({int? heightCm = 178, DateTime? nicknameChangeableAt}) => MyProfile(
      nickname: '늑대',
      age: 24,
      university: '가나대학교',
      major: '경영학과',
      heightCm: heightCm,
      mbti: 'ENFP',
      avatarUrl: null,
      preferredAgeMin: null,
      preferredAgeMax: null,
      preferredHeightMin: null,
      preferredHeightMax: null,
      bio: null,
      nicknameChangeableAt: nicknameChangeableAt,
    );

final _nicknameField = find.byType(TextField).at(0);
final _heightField = find.byType(TextField).at(1);

Finder _valueOf(Finder field) => find.descendant(of: field, matching: find.byType(EditableText));

/// 15-6 기본 정보 수정(pen `mhdYA` · 15-6-2 `ZuPTD` 360×780, 계획서 2026-09-28-me-profile.md A16 화면 대조표).
void main() {
  late FakeMeRepository me;
  late FakeBasicInfoRepository nicknames;
  late ProviderContainer container;

  /// 15-6 이 pop 으로 돌려준 값. 아직 안 돌아왔으면 'open'.
  late Object? popped;

  void usePenFrame(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> openBasicInfo(WidgetTester tester) async {
    await tester.tap(find.text('15-5'));
    await tester.pumpAndSettle();
  }

  /// 15-5 자리(내 프로필을 보고 있는 앞 화면) 위에 15-6 을 올린다.
  Future<void> pump(WidgetTester tester, {MyProfile? profile}) async {
    me = FakeMeRepository(Success(profile ?? _profile()));
    nicknames = FakeBasicInfoRepository();
    popped = 'open';
    container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(me),
        basicInfoRepositoryProvider.overrideWithValue(nicknames),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: AppRoutes.myProfileManage,
      routes: [
        GoRoute(
          path: AppRoutes.myProfileManage,
          builder: (context, state) => Consumer(
            builder: (context, ref, _) {
              ref.watch(myProfileProvider);
              return Scaffold(
                body: TextButton(
                  onPressed: () async => popped = await context.push<bool>(AppRoutes.myBasicInfo),
                  child: const Text('15-5'),
                ),
              );
            },
          ),
        ),
        GoRoute(path: AppRoutes.myBasicInfo, builder: (context, state) => const BasicInfoEditScreen()),
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
    await openBasicInfo(tester);
  }

  AppButton saveButton(WidgetTester tester) => tester.widget<AppButton>(find.byType(AppButton));

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byType(AppButton));
    await tester.pump();
  }

  /// 닉네임을 치고 중복 확인(300ms 디바운스)까지 끝낸다.
  Future<void> typeNickname(WidgetTester tester, String nickname) async {
    await tester.enterText(_nicknameField, nickname);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  OutlineInputBorder border(WidgetTester tester, Finder field, {bool disabled = false}) {
    final decoration = tester.widget<TextField>(field).decoration!;
    return (disabled ? decoration.disabledBorder : decoration.enabledBorder)! as OutlineInputBorder;
  }

  group('15-6 `mhdYA` pen 값(배율 1.0, 360×780)', () {
    testWidgets('앱바 `m2PTHo` — 편집 앱바(B7), 제목 "기본 정보 수정", 내비 없음', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(tester.widget<EditAppBar>(find.byType(EditAppBar)).title, '기본 정보 수정');
      expect(tester.getRect(find.byType(EditAppBar)), const Rect.fromLTWH(0, 0, 360, 56));
      expect(find.byType(AppBottomNav), findsNothing);
    });

    testWidgets('본문 `fP8cs` — 위 32 · 좌우 24, 닉네임 칸 → 16 → 키 칸, 라벨 ↔ 상자 ↔ helper 8', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      // 닉네임 `G1tl8` (24, 32) — 앱바 56 아래라 화면 y88. 라벨 렌더 20 → 8 → 상자 `TDM1r` 52(2026-10-01 개편, 옛 56) → 8 → helper 17.
      expect(tester.getTopLeft(find.text('닉네임')), const Offset(24, 88));
      expect(tester.getSize(find.text('닉네임')).height, 20);
      expect(tester.getRect(_nicknameField), const Rect.fromLTWH(24, 116, 312, 52));
      final helper = find.text('30일에 한 번 바꿀 수 있어요');
      expect(tester.getTopLeft(helper).dy, 176);
      expect(tester.getSize(helper).height, 17);
      // 키 줄 `Z7OpEp` — 닉네임 칸 끝(y193) 16 아래.
      expect(tester.getTopLeft(find.text('키 (cm)')), const Offset(24, 209));
      expect(tester.getRect(_heightField), const Rect.fromLTWH(24, 237, 312, 52));
    });

    testWidgets('라벨 14/600 body · 상자 surface-soft · 모서리 12 · 테두리 hairline 1(`TDM1r` 2026-10-01 개편)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      for (final (label, field) in [('닉네임', _nicknameField), ('키 (cm)', _heightField)]) {
        final style = tester.widget<Text>(find.text(label)).style!;
        expect((style.fontSize, style.fontWeight, style.color), (14, FontWeight.w600, AppColors.body));
        final decoration = tester.widget<TextField>(field).decoration!;
        expect((decoration.filled, decoration.fillColor), (true, AppColors.surfaceSoft));
        final outline = border(tester, field);
        expect((outline.borderSide.color, outline.borderSide.width), (AppColors.hairline, 1));
        expect(outline.borderRadius, BorderRadius.circular(12));
      }
    });

    testWidgets('값 16/400 — 닉네임 "늑대" 도 키 "178" 도 ink(B1 — pen `BdRVU` 의 #929292 는 자리표시 색)', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      for (final (field, value) in [(_nicknameField, '늑대'), (_heightField, '178')]) {
        final editable = tester.widget<EditableText>(_valueOf(field));
        expect(editable.controller.text, value);
        expect((editable.style.fontSize, editable.style.fontWeight, editable.style.color), (16, FontWeight.w400, AppColors.ink));
      }
    });

    testWidgets('값은 상자 안 왼쪽 16 · 세로 가운데(pen padding [0,16])', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      for (final field in [_nicknameField, _heightField]) {
        expect(tester.getTopLeft(_valueOf(field)).dx, 24 + 16);
        expect(tester.getCenter(_valueOf(field)).dy, closeTo(tester.getCenter(field).dy, 0.5));
      }
    });

    testWidgets('닉네임 helper — info 14 muted + gap 4 + "30일에 한 번 바꿀 수 있어요" 12/400 muted', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      final icon = tester.widget<Icon>(find.byIcon(AppIcons.info));
      expect((icon.size, icon.color), (14, AppColors.muted));
      final text = find.text('30일에 한 번 바꿀 수 있어요');
      final style = tester.widget<Text>(text).style!;
      expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w400, AppColors.muted));
      expect(tester.getTopLeft(find.byIcon(AppIcons.info)).dx, 24);
      expect(tester.getTopLeft(text).dx, 24 + 14 + 4);
      expect(tester.getCenter(find.byIcon(AppIcons.info)).dy, closeTo(tester.getCenter(text).dy, 0.5));
    });

    testWidgets('키 칸은 helper 가 없다 — 오류 때만', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(find.byIcon(AppIcons.circleAlert), findsNothing);
      expect(find.byIcon(AppIcons.info), findsOneWidget);
    });

    testWidgets('"저장" `fx0HX` — 312×52 · 좌우 24 · 화면 아래 8(바닥 고정, Bottom Bar CTA `A8INC6` [8,24,8,24])', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      expect(saveButton(tester).label, '저장');
      expect(tester.getRect(find.byType(AppButton)), const Rect.fromLTWH(24, 780 - 8 - 52, 312, 52));
    });

    testWidgets('출생연도 · 성별 · 실명 · 전화번호 · MBTI 칸은 없다(U6) — 입력 칸은 닉네임 · 키 둘뿐', (tester) async {
      await pump(tester);

      expect(find.byType(TextField), findsNWidgets(2));
      for (final absent in ['출생연도', '성별', '실명', '이름', '전화번호', 'MBTI', '남성', '여성']) {
        expect(find.textContaining(absent), findsNothing, reason: absent);
      }
    });
  });

  group('15-6-2 `ZuPTD` 닉네임 잠김', () {
    testWidgets('`V3sicJ` — 입력 불가, 테두리 hairline 1, 바탕 surface-soft 그대로, 값 disabled', (tester) async {
      usePenFrame(tester);
      await pump(tester, profile: _profile(nicknameChangeableAt: _unlocksAt));

      final field = tester.widget<TextField>(_nicknameField);
      expect(field.enabled, isFalse);
      final outline = border(tester, _nicknameField, disabled: true);
      expect((outline.borderSide.color, outline.borderSide.width), (AppColors.hairline, 1));
      expect(field.decoration!.fillColor, AppColors.surfaceSoft);
      expect(tester.widget<EditableText>(_valueOf(_nicknameField)).style.color, AppColors.disabled);
      // 모양은 그대로, 높이 52 · 모서리 12 만 개편을 따른다(`TDM1r` 2026-10-01).
      expect(tester.getRect(_nicknameField), const Rect.fromLTWH(24, 116, 312, 52));
      expect(outline.borderRadius, BorderRadius.circular(12));
    });

    testWidgets('오른쪽 lock 20 disabled — 상자 오른쪽 16 · 세로 가운데', (tester) async {
      usePenFrame(tester);
      await pump(tester, profile: _profile(nicknameChangeableAt: _unlocksAt));

      final lock = find.descendant(of: _nicknameField, matching: find.byIcon(AppIcons.lock));
      final icon = tester.widget<Icon>(lock);
      expect((icon.size, icon.color), (20, AppColors.disabled));
      expect(tester.getRect(lock).right, 24 + 312 - 16);
      expect(tester.getCenter(lock).dy, tester.getCenter(_nicknameField).dy);
      // 값 칸은 자물쇠 앞 8 에서 끝난다(pen 값 폭 280 → 252).
      expect(tester.getRect(_valueOf(_nicknameField)).right, lessThanOrEqualTo(tester.getRect(lock).left - 8));
    });

    testWidgets('helper — clock-3 14 muted + "10월 27일부터 바꿀 수 있어요"(한국 시각) 12/400 muted', (tester) async {
      usePenFrame(tester);
      await pump(tester, profile: _profile(nicknameChangeableAt: _unlocksAt));

      final icon = tester.widget<Icon>(find.byIcon(AppIcons.clock3));
      expect((icon.size, icon.color), (14, AppColors.muted));
      final style = tester.widget<Text>(find.text('10월 27일부터 바꿀 수 있어요')).style!;
      expect((style.fontSize, style.color), (12, AppColors.muted));
      expect(tester.getTopLeft(find.text('10월 27일부터 바꿀 수 있어요')).dy, 176);
      expect(find.byIcon(AppIcons.info), findsNothing);
      expect(find.text('30일에 한 번 바꿀 수 있어요'), findsNothing);
    });

    testWidgets('잠금 중에도 키는 고칠 수 있다 — 바꾸면 저장이 켜지고 키만 보낸다', (tester) async {
      await pump(tester, profile: _profile(nicknameChangeableAt: _unlocksAt));
      expect(tester.widget<TextField>(_heightField).enabled, isNot(isFalse));
      expect(saveButton(tester).onPressed, isNull);

      await tester.enterText(_heightField, '180');
      await tester.pump();
      expect(saveButton(tester).onPressed, isNotNull);
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(me.updates, [
        {'height_cm': 180},
      ]);
    });
  });

  group('저장 버튼(B2 · B6)', () {
    testWidgets('바뀐 것이 없으면 꺼져 있다 — 키를 바꾸면 켜지고, 되돌리면 다시 꺼진다', (tester) async {
      await pump(tester);
      expect(saveButton(tester).onPressed, isNull);

      await tester.enterText(_heightField, '180');
      await tester.pump();
      expect(saveButton(tester).onPressed, isNotNull);

      await tester.enterText(_heightField, '178');
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('저장 중에는 버튼이 흰 스피너로 바뀐다(B6 · D8)', (tester) async {
      await pump(tester);
      await tester.enterText(_heightField, '180');
      await tester.pump();
      me.holdUpdate = Completer<void>();

      await tapSave(tester);

      expect(saveButton(tester).isLoading, isTrue);
      expect(find.descendant(of: find.byType(AppButton), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      me.holdUpdate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('저장 중에는 칸을 고칠 수 없다 — 보내는 값과 화면 값이 갈라지지 않는다(검토 사소 1, 15-7 과 같음)', (tester) async {
      await pump(tester);
      await tester.enterText(_heightField, '180');
      await tester.pump();
      me.holdUpdate = Completer<void>();

      await tapSave(tester);
      await tester.tap(_heightField, warnIfMissed: false);
      await tester.enterText(_heightField, '190');
      await tester.pump();

      expect(find.text('190'), findsNothing);
      me.holdUpdate!.complete();
      await tester.pumpAndSettle();
      expect(me.updates, [
        {'height_cm': 180},
      ]);
    });

    testWidgets('키만 고쳐 저장하면 본문은 {"height_cm"} 뿐 — 앞 화면으로 true 를 돌려주고 내 프로필을 다시 읽는다', (tester) async {
      await pump(tester);
      await tester.enterText(_heightField, '180');
      await tester.pump();

      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(me.updates, [
        {'height_cm': 180},
      ]);
      expect(popped, isTrue);
      expect(find.byType(BasicInfoEditScreen), findsNothing);
      expect(me.calls, 2);
    });

    testWidgets('닉네임을 고쳐 저장하면 {"nickname"} 뿐', (tester) async {
      await pump(tester);
      await typeNickname(tester, '호랑이');

      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(nicknames.checkedNicknames, ['호랑이']);
      expect(me.updates, [
        {'nickname': '호랑이'},
      ]);
    });

    testWidgets('저장 없이 뒤로 나가면 앞 화면에 아무것도 돌려주지 않는다(토스트 없음)', (tester) async {
      await pump(tester);
      await tester.enterText(_heightField, '180');
      await tester.pump();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(popped, isNull);
      expect(me.updates, isEmpty);
    });
  });

  group('입력 규칙(04-1 과 같다)', () {
    testWidgets('키는 숫자만 3자리까지', (tester) async {
      await pump(tester);
      // 이미 3자리면 04-1 포매터는 더 친 것을 버리고 옛 값을 지킨다 — 비운 뒤 친다.
      await tester.enterText(_heightField, '');

      await tester.enterText(_heightField, '1a8b05');
      await tester.pump();

      expect(tester.widget<EditableText>(_valueOf(_heightField)).controller.text, '180');
    });

    testWidgets('닉네임은 한글 · 영문만', (tester) async {
      await pump(tester);

      await typeNickname(tester, '호랑 이1!');

      expect(tester.widget<EditableText>(_valueOf(_nicknameField)).controller.text, '호랑이');
    });
  });

  group('오류는 칸 아래 빨간 helper(B5 — circle-alert 14 + 12/400 error)', () {
    void expectErrorHelper(WidgetTester tester, String message, {required Finder under, required Finder above}) {
      final text = find.text(message);
      expect(text, findsOneWidget);
      final style = tester.widget<Text>(text).style!;
      expect((style.fontSize, style.fontWeight, style.color), (12, FontWeight.w400, AppColors.error));
      final icon = find.byIcon(AppIcons.circleAlert);
      final iconWidget = tester.widget<Icon>(icon);
      expect((iconWidget.size, iconWidget.color), (14, AppColors.error));
      expect(tester.getTopLeft(text).dy, tester.getBottomLeft(under).dy + 8);
      expect(tester.getBottomLeft(text).dy, lessThan(tester.getTopLeft(above).dy));
    }

    testWidgets('닉네임 중복 — 닉네임 칸 아래, 테두리 error 2, 저장 꺼짐', (tester) async {
      usePenFrame(tester);
      await pump(tester);
      nicknames.nextAvailabilityResult = const Success(false);

      await typeNickname(tester, '호랑이');

      expectErrorHelper(tester, '이미 있는 닉네임이에요', under: _nicknameField, above: find.text('키 (cm)'));
      final outline = border(tester, _nicknameField);
      expect((outline.borderSide.color, outline.borderSide.width), (AppColors.error, 2));
      expect(find.byIcon(AppIcons.info), findsNothing);
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('닉네임 형식 — "한글 또는 영문 2~5자로 입력해 주세요"', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      await typeNickname(tester, '호');

      expectErrorHelper(tester, '한글 또는 영문 2~5자로 입력해 주세요', under: _nicknameField, above: find.text('키 (cm)'));
      expect(saveButton(tester).onPressed, isNull);
    });

    for (final message in ['이미 있는 닉네임이에요', '닉네임은 30일에 한 번 바꿀 수 있어요']) {
      testWidgets('저장 때 서버 409 "$message" — 닉네임 칸 아래(버튼 위 글이 아니다)', (tester) async {
        usePenFrame(tester);
        await pump(tester);
        await typeNickname(tester, '호랑이');
        me.updateResult = FailureResult(ServerRejectedFailure(message));

        await tapSave(tester);
        await tester.pumpAndSettle();

        expectErrorHelper(tester, message, under: _nicknameField, above: find.text('키 (cm)'));
        expect(find.byType(BasicInfoEditScreen), findsOneWidget);
        expect(saveButton(tester).onPressed, isNull);
      });
    }

    testWidgets('키 범위 — 3자리를 다 친 뒤 범위 밖이면 키 칸 아래 "숫자 3자리를 확인해 주세요"', (tester) async {
      usePenFrame(tester);
      await pump(tester);

      await tester.enterText(_heightField, '999');
      await tester.pump();

      expectErrorHelper(tester, '숫자 3자리를 확인해 주세요', under: _heightField, above: find.byType(AppButton));
      final outline = border(tester, _heightField);
      expect((outline.borderSide.color, outline.borderSide.width), (AppColors.error, 2));
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets('저장 때 서버 422 — 키 칸 아래', (tester) async {
      usePenFrame(tester);
      await pump(tester);
      await tester.enterText(_heightField, '180');
      await tester.pump();
      me.updateResult = const FailureResult(ServerRejectedFailure('입력한 값을 다시 확인해 주세요'));

      await tapSave(tester);
      await tester.pumpAndSettle();

      expectErrorHelper(tester, '입력한 값을 다시 확인해 주세요', under: _heightField, above: find.byType(AppButton));
    });

    testWidgets('그 밖의 저장 실패(네트워크)는 04-1 처럼 버튼 위 오류 글(caption · error), 칸은 그대로', (tester) async {
      usePenFrame(tester);
      await pump(tester);
      await tester.enterText(_heightField, '180');
      await tester.pump();
      me.updateResult = const FailureResult(NetworkFailure());

      await tapSave(tester);
      await tester.pumpAndSettle();

      final error = find.text(const NetworkFailure().toDisplayMessage());
      expect(error, findsOneWidget);
      final style = tester.widget<Text>(error).style!;
      expect((style.fontSize, style.color), (12, AppColors.error));
      expect(tester.getBottomLeft(error).dy, lessThan(tester.getTopLeft(find.byType(AppButton)).dy));
      expect(tester.getTopLeft(error).dy, greaterThan(tester.getBottomLeft(_heightField).dy));
      expect(find.byIcon(AppIcons.circleAlert), findsNothing, reason: '칸 탓이 아니다');
      expect(tester.widget<EditableText>(_valueOf(_heightField)).controller.text, '180');
      expect(saveButton(tester).onPressed, isNotNull);
    });
  });

  testWidgets('basic_info_edit_is_filled_from_the_server_each_time_it_opens — 저장 없이 나갔다 다시 열면 서버 값', (tester) async {
    await pump(tester);
    await tester.enterText(_heightField, '180');
    await tester.pump();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await openBasicInfo(tester);

    expect(tester.widget<EditableText>(_valueOf(_heightField)).controller.text, '178');
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('누르는 위젯의 눌림 효과는 제 크기 Material 위에 그린다(COMMON §4-2)', (tester) async {
    usePenFrame(tester);
    await pump(tester);

    // byType 은 정확한 타입만 찾는다 — 버튼 안은 InkResponse 의 하위 클래스 InkWell 이라 술어로 찾는다.
    final inks = find.descendant(
      of: find.byType(BasicInfoEditScreen),
      matching: find.byWidgetPredicate((widget) => widget is InkResponse),
    );
    expect(inks, findsWidgets, reason: '뒤로 · 저장');
    for (final ink in inks.evaluate()) {
      final painter = find.ancestor(of: find.byWidget(ink.widget), matching: find.byType(Material)).first;
      expect(tester.getSize(painter), tester.getSize(find.byWidget(ink.widget)));
    }
  });

  // DESIGN §11.2 — 시스템 글꼴 확대(최대 2.0)에서도 넘치거나 잘리지 않는다. 상자 52(`TDM1r`)는 최소값이다.
  for (final locked in [false, true]) {
    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets('15-6${locked ? '-2' : ''} — 폭 360 · 글자 배율 $scale 에서 넘침 · 잘림이 없다', (tester) async {
        usePenFrame(tester);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pump(tester, profile: _profile(nicknameChangeableAt: locked ? _unlocksAt : null));
        expect(tester.takeException(), isNull);
        final clipped = _clippedTexts();
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await tester.pumpAndSettle();
        clipped.addAll(_clippedTexts());

        expect(tester.takeException(), isNull);
        expect(clipped, isEmpty);
        for (final field in [_nicknameField, _heightField]) {
          expect(tester.getSize(field).height, greaterThanOrEqualTo(52));
          final box = tester.getRect(field);
          final value = tester.getRect(_valueOf(field));
          expect(value.top >= box.top && value.bottom <= box.bottom, isTrue, reason: '값이 상자 밖으로 삐져나간다');
        }
      });
    }
  }
}

/// 고정 상자에 갇혀 오류 없이 잘린 글자. 폭은 배치 때 받은 최대 폭으로 잰다(화면 15 테스트와 같은 방식).
List<String> _clippedTexts() => [
      for (final element in find.byType(RichText).evaluate())
        if (element.renderObject case final RenderParagraph p
            when p.getMaxIntrinsicHeight(p.constraints.maxWidth) > p.size.height + 0.5 ||
                p.getMinIntrinsicWidth(double.infinity) > p.size.width + 0.5)
          p.text.toPlainText(),
    ];
