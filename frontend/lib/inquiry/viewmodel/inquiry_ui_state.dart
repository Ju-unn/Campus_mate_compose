import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/inquiry/model/data/reply_email.dart';

/// 문의하기 화면 하나의 상태(pen 21a ~ 21c).
class InquiryUiState {
  const InquiryUiState({
    this.reason,
    this.body = '',
    this.replyEmail = '',
    this.replyEmailLeft = false,
    this.isSubmitting = false,
    this.error,
    this.submitted = false,
  });

  final InquiryReason? reason;

  /// 내용 원문. 1000자 자르기는 화면 입력기 몫이고 여기서는 다듬어 비었는지만 본다.
  final String body;
  final String replyEmail;

  /// 메일 칸을 한 번 벗어났는가. 쓰는 도중에 곧바로 빨갛게 되지 않도록 오류는 벗어난 뒤에만 띄운다.
  final bool replyEmailLeft;
  final bool isSubmitting;

  /// 보내기 실패("다시 시도"). 글자는 화면이 만든다.
  final Failure? error;

  /// 서버가 받아 줬다. 화면은 이 값이 켜지면 닫고 토스트를 띄운다.
  final bool submitted;

  bool get isReplyEmailValid => isValidReplyEmail(replyEmail);

  /// 메일 칸 아래 빨간 줄. 빈 칸은 오류가 아니다(보내기 버튼이 꺼져 있을 뿐).
  Failure? get emailError => replyEmailLeft && replyEmail.trim().isNotEmpty && !isReplyEmailValid
      ? const AppErrorFailure(AppError.inquiryEmailInvalid)
      : null;

  /// 사유를 골랐고, 내용이 있고, 메일 모양이 맞고, 보내는 중이 아니고, 아직 끝나지 않았을 때.
  bool get canSubmit =>
      reason != null && body.trim().isNotEmpty && isReplyEmailValid && !isSubmitting && !submitted;

  /// [error] 는 넘기지 않으면 지워진다 — 다음 동작을 하면 지난 실패 문구가 사라져야 한다.
  InquiryUiState copyWith({
    InquiryReason? reason,
    String? body,
    String? replyEmail,
    bool? replyEmailLeft,
    bool? isSubmitting,
    Failure? error,
    bool? submitted,
  }) {
    return InquiryUiState(
      reason: reason ?? this.reason,
      body: body ?? this.body,
      replyEmail: replyEmail ?? this.replyEmail,
      replyEmailLeft: replyEmailLeft ?? this.replyEmailLeft,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      submitted: submitted ?? this.submitted,
    );
  }
}
