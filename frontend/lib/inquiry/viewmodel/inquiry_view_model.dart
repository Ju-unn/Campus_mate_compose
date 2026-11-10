import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/inquiry/model/repository/inquiry_account_email_provider.dart';
import 'package:campus_mate/inquiry/model/repository/inquiry_repository_provider.dart';
import 'package:campus_mate/inquiry/viewmodel/inquiry_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 화면 하나에 하나. 닫히면 버려져 다음에 열면 빈 칸에서 시작한다(메일 칸만 계정 메일로 미리 채운다).
final inquiryViewModelProvider =
    NotifierProvider.autoDispose<InquiryViewModel, InquiryUiState>(InquiryViewModel.new);

/// 문의하기(11-08 회의 할 일 6번). 사유 + 내용 + 답장 받을 메일을 서버로 보낸다.
class InquiryViewModel extends Notifier<InquiryUiState> {
  @override
  InquiryUiState build() => InquiryUiState(replyEmail: ref.read(inquiryAccountEmailProvider) ?? '');

  void selectReason(InquiryReason reason) => state = state.copyWith(reason: reason);

  void updateBody(String body) => state = state.copyWith(body: body);

  void updateReplyEmail(String email) => state = state.copyWith(replyEmail: email);

  /// 메일 칸에서 손을 뗐다 — 이제부터 틀린 모양을 빨간 줄로 알린다.
  void finishReplyEmailEdit() => state = state.copyWith(replyEmailLeft: true);

  /// 실패 뒤에 다시 부르면 같은 내용을 그대로 다시 보낸다(쓴 글은 지우지 않는다).
  Future<void> submit() async {
    if (!state.canSubmit) return;
    state = state.copyWith(isSubmitting: true);
    final result = await ref.read(inquiryRepositoryProvider).send(
          reason: state.reason!,
          body: state.body.trim(),
          replyEmail: state.replyEmail.trim(),
        );
    // 응답을 기다리는 동안 화면을 닫으면 autoDispose 로 이미 버려졌다. 서버에는 이미 갔으니 여기서 끝낸다.
    if (!ref.mounted) return;
    state = result.when(
      onSuccess: (_) => state.copyWith(isSubmitting: false, submitted: true),
      onFailure: (failure) => state.copyWith(isSubmitting: false, error: _shown(failure)),
    );
  }

  /// 429 는 이 앱 문구(`AppError.inquiryDailyLimit`)의 종류로 바꿔 낀다 — 공용 문구("잠시 후 다시 시도")는 하루 상한과 맞지 않다
  /// (기다려도 오늘은 안 된다). 나머지는 그 실패 그대로다.
  Failure _shown(Failure failure) =>
      failure is RateLimitedFailure ? const AppErrorFailure(AppError.inquiryDailyLimit) : failure;
}
