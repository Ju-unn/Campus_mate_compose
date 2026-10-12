import 'package:campus_mate/auth/model/social_provider.dart';
import 'package:campus_mate/auth/view/social_login_button.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' show SignInWithAppleButton, SignInWithAppleButtonStyle;

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

/// 버튼 칸(46 높이) 바로 안쪽의 여백.
EdgeInsetsGeometry _contentPadding(WidgetTester tester) => tester
    .widget<Padding>(find.descendant(of: find.byType(InkWell), matching: find.byType(Padding)).first)
    .padding;

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

    // 대장 지시문 15(디자인 파일 값): 굵기 500.
    testWidgets('레이블 굵기는 500', (tester) async {
      await _pump(tester, SocialProvider.kakao, onPressed: () {});

      expect(_renderedStyle(tester, '카카오 로그인').fontWeight, FontWeight.w500);
    });

    // 대장 지시문 15(디자인 파일 값): 진행 중 스피너 20×20, 색은 레이블과 같은 검정 85%.
    testWidgets('진행 중 스피너는 20×20, 검정 85%', (tester) async {
      await _pump(tester, SocialProvider.kakao, onPressed: () {}, isLoading: true);

      expect(tester.getSize(find.byType(CircularProgressIndicator)), const Size(20, 20));
      expect(tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).color, AppColors.kakaoLabel);
    });

    testWidgets('레이블 글자 크기는 버튼 높이의 1/3 이하', (tester) async {
      await _pump(tester, SocialProvider.kakao, onPressed: () {});

      expect(_renderedStyle(tester, '카카오 로그인').fontSize, lessThanOrEqualTo(46 / 3));
    });

    // 대장 지시문 15(디자인 파일 값): 심볼은 공식 도형 원래 크기 13×13 그대로(키우지 않는다).
    testWidgets('심볼은 13×13, 레이블과 8 떨어져 함께 가운데 정렬', (tester) async {
      await _pump(tester, SocialProvider.kakao, onPressed: () {});

      final symbol = tester.getRect(find.byKey(SocialLoginButton.markKey));
      final label = tester.getRect(find.text('카카오 로그인'));
      final button = tester.getRect(find.byType(SocialLoginButton));
      expect(symbol.size, const Size(13, 13));
      expect(label.left - symbol.right, moreOrLessEquals(8, epsilon: 0.01));
      final groupCenter = (symbol.left + label.right) / 2;
      expect(groupCenter, moreOrLessEquals(button.center.dx, epsilon: 0.5));
    });

    // 후속 지시문 13 B-2: 카카오는 안쪽 좌우 padding 을 따로 두지 않는다(구글만 12).
    testWidgets('안쪽 좌우 여백 없이 심볼과 레이블만 가운데 정렬한다', (tester) async {
      await _pump(tester, SocialProvider.kakao, onPressed: () {});

      expect(_contentPadding(tester), EdgeInsets.zero);
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

    testWidgets('안쪽 좌우 여백은 12', (tester) async {
      await _pump(tester, SocialProvider.google, onPressed: () {});

      expect(_contentPadding(tester), const EdgeInsets.symmetric(horizontal: 12));
    });

    testWidgets('읽기 이름은 "Google 계정으로 로그인"', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, SocialProvider.google, onPressed: () {});

      expect(find.bySemanticsLabel('Google 계정으로 로그인'), findsOneWidget);
      handle.dispose();
    });
  });

  // pen `n4d2T3`(SocialButton/Apple): 높이 46, 모서리 12, 폭 칸 전체, 바탕 #000000, 애플 공식 "Apple로 로그인".
  group('애플', () {
    Finder appleButton() => find.byType(SignInWithAppleButton);
    Finder inner() => find.descendant(of: appleButton(), matching: find.byType(CupertinoButton));

    /// 패키지 버튼이 실제로 칠한 바탕색.
    Color? paintedColor(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(find.descendant(of: inner(), matching: find.byType(DecoratedBox)).first);
      return (box.decoration as ShapeDecoration).color;
    }

    testWidgets('폭은 칸 전체(312), 높이 46, 모서리 12, 바탕 #000000, 문구 "Apple로 로그인"', (tester) async {
      await _pump(tester, SocialProvider.apple, onPressed: () {});

      expect(tester.getSize(find.byType(SocialLoginButton)), const Size(312, 46));
      expect(tester.getSize(appleButton()), const Size(312, 46));
      final button = tester.widget<SignInWithAppleButton>(appleButton());
      expect(button.height, 46);
      expect(button.borderRadius, BorderRadius.circular(12));
      expect(button.text, 'Apple로 로그인');
      expect(button.style, SignInWithAppleButtonStyle.black);
      expect(paintedColor(tester), const Color(0xFF000000));
    });

    testWidgets('누르면 onPressed 를 한 번 부른다', (tester) async {
      var taps = 0;
      await _pump(tester, SocialProvider.apple, onPressed: () => taps++);

      await tester.tap(find.byType(SocialLoginButton));

      expect(taps, 1);
    });

    testWidgets('비활성이어도 검정 그대로이고(패키지의 회색 비활성 색을 쓰지 않는다) 눌리지 않는다', (tester) async {
      await _pump(tester, SocialProvider.apple);

      expect(paintedColor(tester), const Color(0xFF000000));
      expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
    });

    testWidgets('누르는 동안 패키지 버튼은 흐려지지 않고, 눌림은 버튼 크기의 잉크로만 보인다', (tester) async {
      await _pump(tester, SocialProvider.apple, onPressed: () {});

      final gesture = await tester.startGesture(tester.getCenter(find.byType(SocialLoginButton)));
      await tester.pump(const Duration(milliseconds: 300));

      final fade = tester.widget<FadeTransition>(find.descendant(of: inner(), matching: find.byType(FadeTransition)));
      expect(fade.opacity.value, 1);
      // 잉크는 화면이 아니라 버튼 크기의 Material 위에 그려진다(COMMON §4-2), 그 Material 은 패키지 버튼 위에 있다.
      final ink = find.ancestor(of: find.byType(InkWell), matching: find.byType(Material)).first;
      expect(tester.getSize(ink), const Size(312, 46));
      await gesture.up();
    });

    testWidgets('진행 중이면 공식 버튼은 그대로 두고 위에 반투명 덮개와 흰 스피너 20×20 을 겹치며, 눌리지 않는다', (tester) async {
      var taps = 0;
      await _pump(tester, SocialProvider.apple, onPressed: () => taps++, isLoading: true);

      expect(find.text('Apple로 로그인'), findsOneWidget);
      expect(paintedColor(tester), const Color(0xFF000000));
      final overlay = find.byKey(SocialLoginButton.busyOverlayKey);
      expect(tester.getRect(overlay), tester.getRect(find.byType(SocialLoginButton)));
      final decoration = tester.widget<DecoratedBox>(overlay).decoration as ShapeDecoration;
      expect(decoration.color, AppColors.scrim);
      final spinner = find.descendant(of: overlay, matching: find.byType(CircularProgressIndicator));
      expect(tester.getSize(spinner), const Size(20, 20));
      expect(tester.widget<CircularProgressIndicator>(spinner).color, AppColors.onInk);
      await tester.tap(find.byType(SocialLoginButton));
      expect(taps, 0);
    });

    testWidgets('읽기 이름은 "Apple로 로그인" 하나뿐인 버튼이다', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, SocialProvider.apple, onPressed: () {});

      expect(find.bySemanticsLabel('Apple로 로그인'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(SocialLoginButton)),
        matchesSemantics(
          label: 'Apple로 로그인',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    for (final scale in [1.5, 2.0, 3.0]) {
      testWidgets('글자 $scale배에서도 넘치지 않고 높이 46, 문구가 버튼 안에 한 줄로 남는다(애플 시스템 버튼처럼 배율을 따르지 않는다)',
          (tester) async {
        await _pump(tester, SocialProvider.apple, onPressed: () {}, textScale: scale);

        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(SocialLoginButton)).height, 46);
        final label = tester.getRect(find.text('Apple로 로그인'));
        final button = tester.getRect(find.byType(SocialLoginButton));
        expect(button.contains(label.topLeft) && button.contains(label.bottomRight), isTrue);
        expect(label.height, lessThan(46));
      });
    }
  });

  // 안쪽 InkWell 의 읽기 동작은 excludeSemantics 가 지운다 — 바깥 읽기 노드가 직접 '누르기' 를 가져야
  // 화면 읽기(TalkBack · VoiceOver)의 두 번 탭 · 스위치 제어가 버튼을 누른다.
  group('화면 읽기 누르기 동작', () {
    const labels = {
      SocialProvider.kakao: SocialLoginLabels.kakaoSemantics,
      SocialProvider.google: SocialLoginLabels.googleSemantics,
      SocialProvider.apple: SocialLoginLabels.appleSemantics,
    };

    SemanticsNode node(WidgetTester tester) => tester.getSemantics(find.byType(SocialLoginButton));

    bool canTap(WidgetTester tester) => node(tester).getSemanticsData().hasAction(SemanticsAction.tap);

    for (final provider in SocialProvider.values) {
      testWidgets('${provider.name}: 켜져 있으면 읽기 노드에 누르기가 있고, 그 동작이 onPressed 를 부른다', (tester) async {
        final handle = tester.ensureSemantics();
        var taps = 0;
        await _pump(tester, provider, onPressed: () => taps++);

        expect(node(tester).label, labels[provider]);
        expect(canTap(tester), isTrue);
        node(tester).owner!.performAction(node(tester).id, SemanticsAction.tap);
        await tester.pump();
        expect(taps, 1);
        handle.dispose();
      });

      testWidgets('${provider.name}: 비활성 · 진행 중이면 읽기 노드에 누르기가 없다', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, provider);
        expect(canTap(tester), isFalse);

        await _pump(tester, provider, onPressed: () {}, isLoading: true);
        expect(canTap(tester), isFalse);
        handle.dispose();
      });
    }
  });
}
