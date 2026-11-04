import 'package:campus_mate/auth/social/model/repository/social_login_repository_provider.dart';
import 'package:campus_mate/auth/social/view/reviewer_login_sheet.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/core/analytics/analytics_provider.dart';
import 'package:campus_mate/core/theme/app_theme.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/analytics/fake_analytics_service.dart';
import '../model/repository/fake_social_login_repository.dart';

// 이 파일의 이메일 · 비밀번호는 모두 가짜다.
const _email = 'reviewer@example.test';
const _password = 'fake-password-1';

const _openButton = ValueKey('open-reviewer-sheet');

/// 시트를 띄우는 단추 하나뿐인 화면. 시트가 닫혔는지는 단추가 다시 눌리는지로 본다.
Future<(FakeSocialLoginRepository, FakeAnalyticsService)> _pump(WidgetTester tester) async {
  final repository = FakeSocialLoginRepository();
  final analytics = FakeAnalyticsService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        socialLoginRepositoryProvider.overrideWithValue(repository),
        analyticsServiceProvider.overrideWithValue(analytics),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: _openButton,
              onPressed: () => showReviewerLoginSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  return (repository, analytics);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(_openButton));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(LabeledField, label);

TextField _textFieldOf(WidgetTester tester, String label) =>
    tester.widget<TextField>(find.descendant(of: _field(label), matching: find.byType(TextField)));

Future<void> _fill(WidgetTester tester, {String email = _email, String password = _password}) async {
  await tester.enterText(find.descendant(of: _field('Email'), matching: find.byType(TextField)), email);
  await tester.enterText(find.descendant(of: _field('Password'), matching: find.byType(TextField)), password);
  await tester.pump();
}

Finder _signIn() => find.widgetWithText(AppButton, 'Sign in');

/// 로그인 단추 — 진행 중에는 글자가 스피너로 바뀌므로 글자 대신 순서(첫 단추)로 찾는다.
Finder _primary() => find.byType(AppButton).first;

Finder _close() => find.widgetWithText(AppButton, 'Close');

bool _isEnabled(WidgetTester tester, Finder button) => tester.widget<AppButton>(button).onPressed != null;

void main() {
  testWidgets('심사원용이라 영어 라벨이다 — Reviewer sign-in · Email · Password · Sign in · Close', (tester) async {
    await _pump(tester);
    await _open(tester);

    expect(find.text('Reviewer sign-in'), findsOneWidget);
    expect(_field('Email'), findsOneWidget);
    expect(_field('Password'), findsOneWidget);
    expect(_signIn(), findsOneWidget);
    expect(_close(), findsOneWidget);
  });

  testWidgets('비밀번호 칸은 글자를 가리고, 이메일 칸은 가리지 않는다(이메일 자판)', (tester) async {
    await _pump(tester);
    await _open(tester);

    expect(_textFieldOf(tester, 'Password').obscureText, isTrue);
    expect(_textFieldOf(tester, 'Email').obscureText, isFalse);
    expect(_textFieldOf(tester, 'Email').keyboardType, TextInputType.emailAddress);
  });

  testWidgets('가입 · 비밀번호 찾기는 없다 — 단추는 Sign in 과 Close 둘뿐이다', (tester) async {
    await _pump(tester);
    await _open(tester);

    expect(find.byType(AppButton), findsNWidgets(2));
    expect(find.textContaining(RegExp('sign up|register|create|forgot|reset|가입|찾기|재설정', caseSensitive: false)), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  group('빈 칸 제출 막기', () {
    testWidgets('처음에는 Sign in 이 눌리지 않는다', (tester) async {
      await _pump(tester);
      await _open(tester);

      expect(_isEnabled(tester, _signIn()), isFalse);
    });

    testWidgets('이메일만 · 비밀번호만 채우면 눌리지 않고, 둘 다 채우면 눌린다', (tester) async {
      await _pump(tester);
      await _open(tester);

      await _fill(tester, password: '');
      expect(_isEnabled(tester, _signIn()), isFalse);
      await _fill(tester, email: '');
      expect(_isEnabled(tester, _signIn()), isFalse);
      await _fill(tester);
      expect(_isEnabled(tester, _signIn()), isTrue);
    });

    testWidgets('이메일이 공백뿐이면 눌리지 않는다', (tester) async {
      await _pump(tester);
      await _open(tester);

      await _fill(tester, email: '   ');

      expect(_isEnabled(tester, _signIn()), isFalse);
    });
  });

  group('로그인', () {
    testWidgets('누르면 입력한 이메일 · 비밀번호를 저장소에 넘기고, 진행 중에는 스피너를 돌리며 다시 눌러도 한 번만 보낸다', (tester) async {
      final (repository, _) = await _pump(tester);
      await _open(tester);
      await _fill(tester);

      await tester.tap(_signIn());
      await tester.pump();
      await tester.tap(_primary());
      await tester.pump();

      expect(repository.passwordRequests, [(_email, _password)]);
      expect(tester.widget<AppButton>(_primary()).isLoading, isTrue);
      expect(find.descendant(of: _primary(), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    });

    testWidgets('성공하면 시트가 닫히고, 로그인 분석 이벤트는 남지 않는다', (tester) async {
      final (repository, analytics) = await _pump(tester);
      await _open(tester);
      await _fill(tester);

      await tester.tap(_signIn());
      repository.passwordCompleter.complete(const Success(null));
      await tester.pumpAndSettle();

      expect(find.text('Reviewer sign-in'), findsNothing);
      expect(analytics.calls, isEmpty);
    });

    testWidgets('잘못된 자격이면 기존 로그인 실패 문구를 보이고, 시트는 열린 채 입력도 그대로다', (tester) async {
      final (repository, _) = await _pump(tester);
      await _open(tester);
      await _fill(tester);

      await tester.tap(_signIn());
      repository.passwordCompleter.complete(const FailureResult(SocialLoginFailure()));
      await tester.pumpAndSettle();

      expect(find.text(AppLocalizationsKo().errorSocialLogin), findsOneWidget);
      expect(find.text('Reviewer sign-in'), findsOneWidget);
      expect(tester.widget<TextField>(find.descendant(of: _field('Email'), matching: find.byType(TextField))).controller!.text, _email);
      expect(_isEnabled(tester, _signIn()), isTrue, reason: '다시 시도할 수 있다');
    });

    testWidgets('한도에 걸리면(429) 기존 한도 문구를 보인다', (tester) async {
      final (repository, _) = await _pump(tester);
      await _open(tester);
      await _fill(tester);

      await tester.tap(_signIn());
      repository.passwordCompleter.complete(const FailureResult(RateLimitedFailure()));
      await tester.pumpAndSettle();

      expect(find.text(AppLocalizationsKo().errorRateLimited), findsOneWidget);
    });
  });

  group('닫기', () {
    testWidgets('Close 를 누르면 닫히고, 다시 열면 입력이 모두 비어 있다', (tester) async {
      await _pump(tester);
      await _open(tester);
      await _fill(tester);

      await tester.tap(_close());
      await tester.pumpAndSettle();
      expect(find.text('Reviewer sign-in'), findsNothing);
      await _open(tester);

      expect(tester.widget<TextField>(find.descendant(of: _field('Email'), matching: find.byType(TextField))).controller!.text, isEmpty);
      expect(tester.widget<TextField>(find.descendant(of: _field('Password'), matching: find.byType(TextField))).controller!.text, isEmpty);
      expect(_isEnabled(tester, _signIn()), isFalse);
    });

    testWidgets('실패 표시도 닫았다 열면 사라진다', (tester) async {
      final (repository, _) = await _pump(tester);
      await _open(tester);
      await _fill(tester);
      await tester.tap(_signIn());
      repository.passwordCompleter.complete(const FailureResult(SocialLoginFailure()));
      await tester.pumpAndSettle();
      await tester.tap(_close());
      await tester.pumpAndSettle();

      await _open(tester);

      expect(find.text(AppLocalizationsKo().errorSocialLogin), findsNothing);
    });

    testWidgets('바깥(어두운 배경)을 눌러 닫아도 입력이 비워진다', (tester) async {
      await _pump(tester);
      await _open(tester);
      await _fill(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await _open(tester);

      expect(tester.widget<TextField>(find.descendant(of: _field('Password'), matching: find.byType(TextField))).controller!.text, isEmpty);
    });
  });

  testWidgets('글자를 2배로 키우고 작은 화면(320×568)에 키보드가 올라와도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester);
    await _open(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AppButton), findsNWidgets(2));
  });
}
