import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/view/social_login_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 화면 폭 360 − 좌우 24 = 312 짜리 칸에 버튼 하나를 앱 테마로 띄운다.
Future<void> _pump(
  WidgetTester tester,
  SocialProvider provider, {
  VoidCallback? onPressed,
  bool isLoading = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: const Size(360, 640), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: SocialLoginButton(provider: provider, onPressed: onPressed, isLoading: isLoading),
            ),
          ),
        ),
      ),
    ),
  );
}

Material _material(WidgetTester tester) => tester.widget<Material>(
      find.descendant(of: find.byType(SocialLoginButton), matching: find.byType(Material)).first,
    );

RoundedRectangleBorder _shape(WidgetTester tester) => _material(tester).shape! as RoundedRectangleBorder;

/// 화면에 실제로 그려진 글자 모양(DefaultTextStyle 과 합쳐진 뒤의 값).
TextStyle _renderedStyle(WidgetTester tester, String text) {
  final rich = tester.widget<RichText>(find.descendant(of: find.text(text), matching: find.byType(RichText)));
  return rich.text.style!;
}

void main() {
  group('공통 규격', () {
    for (final provider in [SocialProvider.kakao, SocialProvider.google]) {
      testWidgets('${provider.name}: 폭은 칸 전체(360 − 24×2), 높이 46, 모서리 12', (tester) async {
        await _pump(tester, provider, onPressed: () {});

        expect(tester.getSize(find.byType(SocialLoginButton)), const Size(312, 46));
        expect(_shape(tester).borderRadius, BorderRadius.circular(12));
      });

      testWidgets('${provider.name}: 누르면 onPressed 를 부른다', (tester) async {
        var taps = 0;
        await _pump(tester, provider, onPressed: () => taps++);

        await tester.tap(find.byType(SocialLoginButton));

        expect(taps, 1);
      });

      testWidgets('${provider.name}: 비활성이어도 브랜드 색은 그대로이고 눌리지 않는다', (tester) async {
        await _pump(tester, provider, onPressed: () {});
        final enabledColor = _material(tester).color;

        await _pump(tester, provider);

        expect(_material(tester).color, enabledColor);
        expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
      });

      testWidgets('${provider.name}: 로딩이면 레이블 대신 스피너, 심볼 · 로고는 남고, 눌리지 않는다', (tester) async {
        var taps = 0;
        await _pump(tester, provider, onPressed: () => taps++, isLoading: true);

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text(SocialLoginLabels.kakao), findsNothing);
        expect(find.text(SocialLoginLabels.google), findsNothing);
        expect(find.byKey(SocialLoginButton.markKey), findsOneWidget);
        await tester.tap(find.byType(SocialLoginButton));
        expect(taps, 0);
      });

      testWidgets('${provider.name}: 글자 2.0배에서도 넘치지 않고 레이블이 한 줄로 버튼 안에 들어간다', (tester) async {
        await _pump(tester, provider, onPressed: () {}, textScale: 2);

        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(SocialLoginButton)).height, 46);
        final label = provider == SocialProvider.kakao ? SocialLoginLabels.kakao : SocialLoginLabels.google;
        final labelRect = tester.getRect(find.text(label));
        final buttonRect = tester.getRect(find.byType(SocialLoginButton));
        expect(buttonRect.contains(labelRect.topLeft) && buttonRect.contains(labelRect.bottomRight), isTrue);
      });
    }
  });

  group('카카오', () {
    testWidgets('바탕 #FEE500, 레이블 "카카오 로그인" 은 검정 85%', (tester) async {
      await _pump(tester, SocialProvider.kakao, onPressed: () {});

      expect(_material(tester).color, AppColors.kakaoContainer);
      expect(_renderedStyle(tester, '카카오 로그인').color, AppColors.kakaoLabel);
    });

    testWidgets('레이블은 앱 기본 글꼴(Pretendard)을 물려받지 않고 OS 기본 서체로 그린다', (tester) async {
      await _pump(tester, SocialProvider.kakao, onPressed: () {});

      final style = _renderedStyle(tester, '카카오 로그인');
      expect(style.inherit, isFalse);
      expect(style.fontFamily, isNull);
      expect(style.fontFamilyFallback, isNull);
    });

    testWidgets('레이블 글자 크기는 버튼 높이의 1/3 이하', (tester) async {
      await _pump(tester, SocialProvider.kakao, onPressed: () {});

      expect(_renderedStyle(tester, '카카오 로그인').fontSize, lessThanOrEqualTo(46 / 3));
    });

    testWidgets('심볼은 약 18×18, 레이블과 8 떨어져 함께 가운데 정렬', (tester) async {
      await _pump(tester, SocialProvider.kakao, onPressed: () {});

      final symbol = tester.getRect(find.byKey(SocialLoginButton.markKey));
      final label = tester.getRect(find.text('카카오 로그인'));
      final button = tester.getRect(find.byType(SocialLoginButton));
      expect(symbol.size, const Size(18, 18));
      expect(label.left - symbol.right, moreOrLessEquals(8, epsilon: 0.01));
      final groupCenter = (symbol.left + label.right) / 2;
      expect(groupCenter, moreOrLessEquals(button.center.dx, epsilon: 0.5));
    });

    testWidgets('읽기 이름은 "카카오로 로그인"', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, SocialProvider.kakao, onPressed: () {});

      expect(find.bySemanticsLabel('카카오로 로그인'), findsOneWidget);
      handle.dispose();
    });
  });

  group('카카오 심볼 도형', () {
    test('공식 13×13 도형을 비율 그대로 크기만 키운다', () {
      final bounds = kakaoSymbolPath(18).getBounds();

      // 원본 x 173.522~186.478, y 16.5225~29.478 를 (173.5, 16.5) 기준 13 칸에서 18 칸으로.
      const scale = 18 / 13;
      expect(bounds.left, moreOrLessEquals((173.522 - 173.5) * scale, epsilon: 0.01));
      expect(bounds.top, moreOrLessEquals((16.5225 - 16.5) * scale, epsilon: 0.01));
      expect(bounds.right, moreOrLessEquals((186.478 - 173.5) * scale, epsilon: 0.01));
      expect(bounds.bottom, moreOrLessEquals((29.478 - 16.5) * scale, epsilon: 0.01));
    });
  });

  group('구글', () {
    testWidgets('바탕 흰색, 안쪽 1px #747775 획, 레이블 "Google 계정으로 로그인" #1F1F1F', (tester) async {
      await _pump(tester, SocialProvider.google, onPressed: () {});

      expect(_material(tester).color, AppColors.googleContainer);
      final side = _shape(tester).side;
      expect((side.color, side.width, side.strokeAlign), (AppColors.googleStroke, 1, BorderSide.strokeAlignInside));
      expect(_renderedStyle(tester, 'Google 계정으로 로그인').color, AppColors.googleLabel);
    });

    testWidgets('글꼴은 Roboto Medium 14/20', (tester) async {
      await _pump(tester, SocialProvider.google, onPressed: () {});

      final style = _renderedStyle(tester, 'Google 계정으로 로그인');
      expect(style.fontFamily, 'Roboto');
      expect(style.fontWeight, FontWeight.w500);
      expect(style.fontSize, 14);
      expect(style.height! * style.fontSize!, moreOrLessEquals(20));
    });

    testWidgets('로고는 공식 자산 20×20, 로고 앞 12 · 로고와 글자 사이 10', (tester) async {
      await _pump(tester, SocialProvider.google, onPressed: () {});

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, 'assets/images/google_g.png');
      // 자산 PR 이 아직 없는 체크아웃에서도 화면이 깨지지 않게 대신 빈 칸을 그린다.
      expect(image.errorBuilder, isNotNull);
      final logo = tester.getRect(find.byKey(SocialLoginButton.markKey));
      final label = tester.getRect(find.text('Google 계정으로 로그인'));
      expect(logo.size, const Size(20, 20));
      expect(label.left - logo.right, moreOrLessEquals(10, epsilon: 0.01));
    });

    testWidgets('글자를 키워 칸이 모자라면 로고 앞 12 · 글자 뒤 12 를 지킨 채 레이블이 줄어든다', (tester) async {
      await _pump(tester, SocialProvider.google, onPressed: () {}, textScale: 2);

      final button = tester.getRect(find.byType(SocialLoginButton));
      final logo = tester.getRect(find.byKey(SocialLoginButton.markKey));
      final label = tester.getRect(find.text('Google 계정으로 로그인'));
      expect(logo.left - button.left, greaterThanOrEqualTo(12 - 0.01));
      expect(button.right - label.right, greaterThanOrEqualTo(12 - 0.01));
    });

    testWidgets('읽기 이름은 "Google 계정으로 로그인"', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, SocialProvider.google, onPressed: () {});

      expect(find.bySemanticsLabel('Google 계정으로 로그인'), findsOneWidget);
      handle.dispose();
    });
  });

  testWidgets('애플 버튼은 아직 그리지 않는다(개발자 계정 승인 뒤 별도 PR)', (tester) async {
    await _pump(tester, SocialProvider.apple, onPressed: () {});

    expect(tester.takeException(), isUnimplementedError);
  });
}
