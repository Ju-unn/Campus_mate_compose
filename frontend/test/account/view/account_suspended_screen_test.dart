import 'package:campus_mate/account/view/account_suspended_screen.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/core/auth/sign_out.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int signOutCalls;

  Future<void> pump(WidgetTester tester) async {
    signOutCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [signOutProvider.overrideWithValue(() async => signOutCalls++)],
        child: const MaterialApp(home: AccountSuspendedScreen()),
      ),
    );
  }

  testWidgets('pen e7QaDh 글자를 그대로 보여준다(값표 7절)', (tester) async {
    await pump(tester);

    expect(find.text('이용이 제한된 계정이에요'), findsOneWidget);
    expect(
      find.text('누적된 신고 내용을 검토한 결과, 이용이 제한되었어요. 부적절한 이용이 반복되면 계정이 삭제될 수 있어요.'),
      findsOneWidget,
    );
    expect(find.text('제한 내용이 궁금하거나 잘못된 것 같다면 아래 메일로 알려 주세요.'), findsOneWidget);
    expect(find.text('문의 메일'), findsOneWidget);
    expect(find.text('가입한 학교 메일 주소를 함께 적어 주시면 더 빨리 확인할 수 있어요.'), findsOneWidget);
    expect(find.byIcon(AppIcons.mail), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
  });

  testWidgets('문의 메일 주소가 보인다', (tester) async {
    await pump(tester);

    expect(find.text('appmailerl4538@gmail.com'), findsOneWidget);
    expect(supportEmail, 'appmailerl4538@gmail.com');
  });

  testWidgets('슬픈 마스코트 120(pen U7msJ)', (tester) async {
    await pump(tester);

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'assets/images/mascot-female-sad.png');
    expect(tester.getSize(find.byType(Image)), const Size(120, 120));
  });

  testWidgets('"로그아웃"을 누르면 signOutProvider 를 한 번 부른다', (tester) async {
    await pump(tester);

    await tester.tap(find.text('로그아웃'));
    await tester.pump();

    expect(signOutCalls, 1);
  });

  testWidgets('로그아웃은 하단 주색 AppButton 이다(pen Yfzmv)', (tester) async {
    await pump(tester);

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.variant, AppButtonVariant.primary);
    // 화면 아래 여백 40(pen 프레임 padding bottom).
    expect(tester.getRect(find.byType(AppButton)).bottom, 600 - 40);
  });

  testWidgets('앱바 · 하단 내비가 없다', (tester) async {
    await pump(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(AppBottomNav), findsNothing);
  });

  testWidgets('360×780 · 글자 배율 2.0 에서도 넘치지 않고 로그아웃이 보인다', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(AppButton)).bottom, lessThanOrEqualTo(780));
  });
}
