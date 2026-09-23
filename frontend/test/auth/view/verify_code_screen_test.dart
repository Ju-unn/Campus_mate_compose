import 'dart:async';

import 'package:campus_mate/auth/model/auth_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/view/verify_code_screen.dart';
import 'package:campus_mate/auth/viewmodel/verify_code_view_model.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../model/fake_auth_repository.dart';

void main() {
  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    FakeAuthRepository? repository,
  }) async {
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository ?? FakeAuthRepository())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: VerifyCodeScreen(email: email)),
      ),
    );
    return container;
  }

  testWidgets('안내 문구·만료 타이머·메일 다시 받기를 보여준다(pen VuiDi)', (tester) async {
    await pumpScreen(tester);

    expect(find.text('인증 코드를 입력해요'), findsOneWidget);
    expect(find.text('hong@snu.ac.kr 로 6자리 숫자를 보냈어요'), findsOneWidget);
    expect(find.textContaining('뒤에 만료돼요'), findsOneWidget);
    expect(find.text('메일 다시 받기'), findsOneWidget);
  });

  testWidgets('입력한 숫자를 여섯 칸에 한 글자씩 그린다', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), '123');
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('메일을 다시 받으면 입력칸이 비고 버튼이 쿨다운 동안 꺼진다', (tester) async {
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();

    await tester.tap(find.text('메일 다시 받기'));
    await tester.pump(const Duration(milliseconds: 1));

    // 새 코드가 오는데 예전 숫자가 남아 있으면 그대로 제출된다.
    expect(find.text('1'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    // 쿨다운 동안 눌러도 아무 일이 없으므로 버튼을 끄고 남은 초를 보여준다.
    final resend = tester.widget<TextButton>(find.widgetWithText(TextButton, '메일 다시 받기 (60초)'));
    expect(resend.enabled, isFalse);
  });

  testWidgets('기한이 지나면 만료 문구가 뜨고 확인 버튼이 꺼진다', (tester) async {
    // 카운트다운은 기기 시계를 보므로 `tester.pump(5분)` 으로는 만료되지 않는다 —
    // 뷰모델의 시각 훅을 과거로 돌리고 메일을 다시 받아 기한이 지난 상태를 만든다.
    final container = await pumpScreen(tester);
    final viewModel = container.read(verifyCodeViewModelProvider(email).notifier)
      ..now = () => DateTime.now().subtract(codeLifetime * 2);
    // 상태는 resend 안에서 곧바로 바뀐다. `await` 하면 가짜 시계가 멈춰 있어 끝나지 않는다.
    unawaited(viewModel.resend());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();

    expect(find.text('코드가 만료됐어요. 메일을 다시 받아 주세요'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '확인')).enabled,
      isFalse,
    );
  });

  testWidgets('코드가 거부되면 여섯 칸 테두리가 오류 색으로 바뀐다', (tester) async {
    final repository = FakeAuthRepository()..nextVerifyOtpResult = const FailureResult(WrongCodeFailure());
    await pumpScreen(tester, repository: repository);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();

    await tester.tap(find.text('확인'));
    await tester.pump(const Duration(milliseconds: 1));

    // pen `Vn6w4` — 테두리 error 2.
    final boxes = tester
        .widgetList<Container>(find.byType(Container))
        .where((box) => (box.decoration as BoxDecoration?)?.border != null)
        .toList();
    final errorBoxes = boxes.where((box) {
      final side = ((box.decoration! as BoxDecoration).border! as Border).top;
      return side.color == AppColors.error && side.width == 2;
    });
    expect(errorBoxes.length, 6);
  });

  testWidgets('앱바가 없다', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('6자리를 모두 입력하기 전에는 CTA 가 비활성이다', (tester) async {
    await pumpScreen(tester);

    // 재전송도 ElevatedButton 이라 .first 대신 라벨로 확인 버튼을 특정한다.
    final button = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '확인'));
    expect(button.enabled, isFalse);
  });

  testWidgets('코드가 틀리면 pen Vn6w4 오류 문구를 보여준다', (tester) async {
    final repository = FakeAuthRepository()..nextVerifyOtpResult = const FailureResult(WrongCodeFailure());
    await pumpScreen(tester, repository: repository);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();

    await tester.tap(find.text('확인'));
    // 만료 타이머가 1초마다 다시 그려 pumpAndSettle 은 끝나지 않는다 — 가짜 저장소의 지연만큼만 민다.
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('코드가 맞지 않아요. 다시 확인해 주세요.'), findsOneWidget);
  });

  testWidgets('검증에 실패하면 에러 문구를 보여준다', (tester) async {
    final repository = FakeAuthRepository()..nextVerifyOtpResult = const FailureResult(UnknownFailure());
    await pumpScreen(tester, repository: repository);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();

    await tester.tap(find.text('확인'));
    // 만료 타이머가 1초마다 다시 그려 pumpAndSettle 은 끝나지 않는다 — 가짜 저장소의 지연만큼만 민다.
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('알 수 없는 오류가 발생했습니다'), findsOneWidget);
  });
}
