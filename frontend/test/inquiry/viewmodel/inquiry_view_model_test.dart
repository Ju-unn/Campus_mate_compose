import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/inquiry/model/repository/inquiry_account_email_provider.dart';
import 'package:campus_mate/inquiry/model/repository/inquiry_repository_provider.dart';
import 'package:campus_mate/inquiry/viewmodel/inquiry_ui_state.dart';
import 'package:campus_mate/inquiry/viewmodel/inquiry_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/repository/fake_inquiry_repository.dart';

void main() {
  late FakeInquiryRepository repository;
  late ProviderContainer container;

  ProviderContainer build({String? accountEmail}) {
    repository = FakeInquiryRepository();
    container = ProviderContainer(
      overrides: [
        inquiryRepositoryProvider.overrideWithValue(repository),
        inquiryAccountEmailProvider.overrideWithValue(accountEmail),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose 라 누군가 보고 있어야 상태가 남는다 — 화면이 떠 있는 동안과 같다.
    container.listen(inquiryViewModelProvider, (_, _) {});
    return container;
  }

  InquiryViewModel viewModel() => container.read(inquiryViewModelProvider.notifier);
  InquiryUiState state() => container.read(inquiryViewModelProvider);

  void fillAll() {
    viewModel()
      ..selectReason(InquiryReason.payment)
      ..updateBody('하트가 안 들어왔어요')
      ..updateReplyEmail('hello@example.com');
  }

  group('처음 상태', () {
    test('아무것도 안 골랐고 보내기를 누를 수 없다', () {
      build();

      expect(state().reason, isNull);
      expect(state().body, '');
      expect(state().replyEmail, '');
      expect(state().canSubmit, isFalse);
    });

    test('계정에서 알 수 있는 메일이 있으면 답장 받을 메일 칸이 미리 채워져 있다', () {
      build(accountEmail: 'me@gmail.com');

      expect(state().replyEmail, 'me@gmail.com');
    });
  });

  group('보내기 버튼', () {
    test('사유 · 내용 · 메일을 다 채워야 누를 수 있다', () {
      build();
      viewModel().selectReason(InquiryReason.bug);
      expect(state().canSubmit, isFalse);
      viewModel().updateBody('앱이 꺼져요');
      expect(state().canSubmit, isFalse);
      viewModel().updateReplyEmail('hello@example.com');
      expect(state().canSubmit, isTrue);
    });

    test('내용이 공백뿐이면 누를 수 없다', () {
      build();
      fillAll();
      viewModel().updateBody('   \n ');

      expect(state().canSubmit, isFalse);
    });

    test('메일 모양이 틀리면 누를 수 없다', () {
      build();
      fillAll();
      viewModel().updateReplyEmail('hello@example');

      expect(state().canSubmit, isFalse);
    });
  });

  group('메일 형식 오류', () {
    test('쓰는 도중에는 띄우지 않고, 칸을 벗어난 뒤에도 틀린 채면 띄운다', () {
      build();
      viewModel().updateReplyEmail('hello@exa');
      expect(state().emailError, isNull);

      viewModel().finishReplyEmailEdit();

      final error = state().emailError;
      expect(error, isA<AppErrorFailure>());
      expect((error! as AppErrorFailure).error, AppError.inquiryEmailInvalid);
    });

    test('빈 칸은 오류가 아니다 — 버튼이 꺼져 있을 뿐이다', () {
      build();
      viewModel().finishReplyEmailEdit();

      expect(state().emailError, isNull);
    });

    test('고쳐서 맞으면 오류가 사라진다', () {
      build();
      viewModel()
        ..updateReplyEmail('hello@exa')
        ..finishReplyEmailEdit()
        ..updateReplyEmail('hello@example.com');

      expect(state().emailError, isNull);
      expect(state().isReplyEmailValid, isTrue);
    });
  });

  group('보내기', () {
    test('다듬은 내용과 메일을 사유 코드와 함께 보내고, 성공하면 끝난 것으로 표시한다', () async {
      build();
      fillAll();
      viewModel()
        ..updateBody('  하트가 안 들어왔어요  ')
        ..updateReplyEmail(' hello@example.com ');

      await viewModel().submit();

      expect(repository.sent, [(reason: InquiryReason.payment, body: '하트가 안 들어왔어요', replyEmail: 'hello@example.com')]);
      expect(state().submitted, isTrue);
      expect(state().isSubmitting, isFalse);
      expect(state().error, isNull);
    });

    test('보내는 중에는 버튼이 꺼지고 한 번 더 불러도 한 번만 간다', () async {
      build();
      fillAll();
      repository.holdSend = Completer<void>();

      final first = viewModel().submit();
      await Future<void>.delayed(Duration.zero);
      expect(state().isSubmitting, isTrue);
      expect(state().canSubmit, isFalse);
      await viewModel().submit();
      repository.holdSend!.complete();
      await first;

      expect(repository.sent, hasLength(1));
    });

    test('다 채우지 않았으면 서버에 가지 않는다', () async {
      build();

      await viewModel().submit();

      expect(repository.sent, isEmpty);
    });

    test('429 하루 상한은 이 앱 문구 종류로 바꿔 보여 주고, 끝난 것은 아니다', () async {
      build();
      fillAll();
      repository.sendResult = const FailureResult(RateLimitedFailure('서버가 준 말'));

      await viewModel().submit();

      final error = state().error;
      expect(error, isA<AppErrorFailure>());
      expect((error! as AppErrorFailure).error, AppError.inquiryDailyLimit);
      expect(state().submitted, isFalse);
      expect(state().isSubmitting, isFalse);
    });

    test('네트워크 실패는 그 실패 그대로 담고, 쓴 글은 남아 다시 보낼 수 있다', () async {
      build();
      fillAll();
      repository.sendResult = const FailureResult(NetworkFailure());

      await viewModel().submit();

      expect(state().error, isA<NetworkFailure>());
      expect(state().body, '하트가 안 들어왔어요');
      expect(state().canSubmit, isTrue);

      repository.sendResult = const Success(null);
      await viewModel().submit();

      expect(repository.sent, hasLength(2));
      expect(state().submitted, isTrue);
      expect(state().error, isNull);
    });

    test('실패 뒤 글을 고치면 지난 실패 문구가 사라진다', () async {
      build();
      fillAll();
      repository.sendResult = const FailureResult(NetworkFailure());
      await viewModel().submit();

      viewModel().updateBody('다시 적었어요');

      expect(state().error, isNull);
    });
  });
}
