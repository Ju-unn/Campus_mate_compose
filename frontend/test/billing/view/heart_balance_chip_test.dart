import 'package:campus_mate/billing/view/heart_balance_chip.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_radius.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../me/model/fake_me_repository.dart';

/// 이름·학교는 지어낸 값이다.
MyProfile _profile(int hearts) => MyProfile(
  nickname: '여우',
  age: 23,
  university: '가나대학교',
  major: '경영학과',
  heightCm: 178,
  mbti: 'ENFP',
  avatarUrl: null,
  photos: const [],
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: 165,
  preferredHeightMax: 180,
  bio: '',
  heartBalance: hearts,
  avatarRegenCost: 10,
);

const _heartAsset = 'assets/images/heart-flat-vector-v3.png';

/// 테스트 글꼴은 pen 의 Pretendard 가 아니라 글자 폭이 넓어서(pen "320" 은 31) 칩 폭은 숫자 폭을 빼고 센다 —
/// "+" 없음 = 8 + 24 + 6 + 숫자 + 12 (pen 에서 81), "+" 켬 = 8 + 24 + 6 + 숫자 + 6 + 16 + 12 (pen 에서 103).
double _chipWidth(WidgetTester tester, String number, {required bool plus}) =>
    8 +
    24 +
    6 +
    tester.getSize(find.text(number)).width +
    (plus ? 6 + 16 : 0) +
    12;

void main() {
  Future<void> pumpView(
    WidgetTester tester,
    int balance, {
    bool showPlus = false,
    VoidCallback? onPlus,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: HeartBalanceChipView(
            balance: balance,
            showPlus: showPlus,
            onPlus: onPlus,
          ),
        ),
      ),
    ),
  );

  final chip = find.byType(HeartBalanceChipView);

  group('모양(pen 마스터 `sysyz`, 인스턴스 높이 44)', () {
    testWidgets(
      '"+" 없음 — 나 탭 `hwVQB/MjtQA` 81×44, 하트 24 (8,10), 숫자 18/700 ink 가 x38',
      (tester) async {
        await pumpView(tester, 320);

        expect(
          tester.getSize(chip),
          Size(_chipWidth(tester, '320', plus: false), 44),
        );
        final origin = tester.getTopLeft(chip);
        final heart = find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName == _heartAsset,
        );
        expect(
          tester.getRect(heart).shift(-origin),
          const Rect.fromLTWH(8, 10, 24, 24),
        );
        final number = tester.widget<Text>(find.text('320')).style!;
        expect(
          (number.fontSize, number.fontWeight, number.color),
          (18, FontWeight.w700, AppColors.ink),
        );
        expect(tester.getTopLeft(find.text('320')).dx - origin.dx, 38);
        expect(find.byIcon(AppIcons.plus), findsNothing);
      },
    );

    testWidgets('바탕 #FFF0F2 · 모서리 pill', (tester) async {
      await pumpView(tester, 320);

      final material = tester.widget<Material>(
        find.descendant(of: chip, matching: find.byType(Material)).first,
      );
      expect(
        (material.color, material.borderRadius),
        (AppColors.primaryWash, BorderRadius.circular(AppRadius.pill)),
      );
      // 눈에 보이는 분홍 띠도 44 — 바깥 상자만 44 면 띠가 37 로 줄어든다.
      expect(
        tester
            .getSize(
              find.descendant(of: chip, matching: find.byType(Material)).first,
            )
            .height,
        44,
      );
    });

    testWidgets('"+" 켬 — 홈 `ihX4y` 103×44, plus 16 #C4224B 는 숫자 뒤 6(x75)', (
      tester,
    ) async {
      await pumpView(tester, 320, showPlus: true, onPlus: () {});

      expect(
        tester.getSize(chip),
        Size(_chipWidth(tester, '320', plus: true), 44),
      );
      final origin = tester.getTopLeft(chip);
      final plus = tester.widget<Icon>(find.byIcon(AppIcons.plus));
      expect((plus.size, plus.color), (16, AppColors.primaryText));
      expect(
        tester.getRect(find.byIcon(AppIcons.plus)).shift(-origin),
        Rect.fromLTWH(
          8 + 24 + 6 + tester.getSize(find.text('320')).width + 6,
          14,
          16,
          16,
        ),
      );
    });

    testWidgets('숫자가 길어지면 칩이 내용 폭에 맞춰 늘어나고, 천 단위마다 쉼표', (tester) async {
      await pumpView(tester, 320);
      final short = tester.getSize(chip).width;
      await pumpView(tester, 12480);

      expect(find.text('12,480'), findsOneWidget);
      expect(tester.getSize(chip).width, greaterThan(short));
      for (final (value, text) in [
        (1000, '1,000'),
        (999, '999'),
        (0, '0'),
        (1234567, '1,234,567'),
      ]) {
        await pumpView(tester, value);
        expect(find.text(text), findsOneWidget, reason: '$value');
      }
    });

    testWidgets('글자 배율을 키워도 숫자는 1.2 배까지만 커진다 — 높이 44 칸과 앱바 제목 자리를 지킨다', (
      tester,
    ) async {
      await pumpView(tester, 320);
      final normal = tester.getSize(find.text('320')).width;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpView(tester, 321);

      expect(tester.getSize(chip).height, 44);
      expect(
        tester.getSize(find.text('321')).width,
        lessThanOrEqualTo(normal * 1.2 + 1),
      );
    });

    testWidgets('"+" 켠 칩도 낭독은 한 번이고 누를 수 있는 버튼으로 읽힌다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpView(tester, 320, showPlus: true, onPlus: () {});

      expect(find.bySemanticsLabel('보유 하트 320개'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('보유 하트 320개')),
        matchesSemantics(
          label: '보유 하트 320개',
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('낭독은 "보유 하트 N개" 한 번 — 숫자와 그림은 따로 읽히지 않는다', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpView(tester, 320);

      expect(find.bySemanticsLabel('보유 하트 320개'), findsOneWidget);
      expect(find.bySemanticsLabel('320'), findsNothing);
      handle.dispose();
    });
  });

  group('"+" 누르기', () {
    testWidgets('"+" 를 켜고 onPlus 를 안 주면 만들 때 걸린다(홈이 콜백을 빠뜨리지 않게)', (
      tester,
    ) async {
      expect(
        () => HeartBalanceChipView(balance: 1, showPlus: true),
        throwsAssertionError,
      );
    });

    testWidgets('켠 칩을 누르면 콜백이 한 번 불린다', (tester) async {
      var taps = 0;
      await pumpView(tester, 320, showPlus: true, onPlus: () => taps++);

      await tester.tap(chip);

      expect(taps, 1);
      // 누름 칸 자체가 44 이상(터치 영역).
      expect(
        tester
            .getSize(find.descendant(of: chip, matching: find.byType(InkWell)))
            .height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('꺼진 칩은 누를 곳이 없다', (tester) async {
      await pumpView(tester, 320);

      expect(
        find.descendant(of: chip, matching: find.byType(InkWell)),
        findsNothing,
      );
    });
  });

  group('서버 값을 읽는 칩 `HeartBalanceChip`', () {
    Future<void> pumpReader(
      WidgetTester tester,
      Result<MyProfile> result, {
      bool settle = true,
      bool showPlus = false,
      VoidCallback? onPlus,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            meRepositoryProvider.overrideWithValue(FakeMeRepository(result)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: HeartBalanceChip(showPlus: showPlus, onPlus: onPlus),
              ),
            ),
          ),
        ),
      );
      if (settle) await tester.pump();
    }

    testWidgets('내 프로필의 heartBalance 를 그대로 보인다(앱에 숫자를 박지 않는다)', (tester) async {
      await pumpReader(tester, Success(_profile(7)));
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('1,000 이상은 쉼표로 보인다', (tester) async {
      await pumpReader(tester, Success(_profile(1250)));
      expect(find.text('1,250'), findsOneWidget);
    });

    testWidgets('읽는 중에는 칩이 없고 자리도 차지하지 않는다', (tester) async {
      await pumpReader(tester, Success(_profile(7)), settle: false);

      expect(chip, findsNothing);
      expect(tester.getSize(find.byType(HeartBalanceChip)), Size.zero);
    });

    testWidgets('읽기에 실패하면 칩이 없다', (tester) async {
      await pumpReader(tester, const FailureResult(NetworkFailure()));

      expect(chip, findsNothing);
    });

    testWidgets('showPlus · onPlus 를 칩에 넘긴다', (tester) async {
      var taps = 0;
      await pumpReader(
        tester,
        Success(_profile(320)),
        showPlus: true,
        onPlus: () => taps++,
      );

      expect(
        tester.getSize(chip),
        Size(_chipWidth(tester, '320', plus: true), 44),
      );
      await tester.tap(chip);
      expect(taps, 1);
    });
  });
}
