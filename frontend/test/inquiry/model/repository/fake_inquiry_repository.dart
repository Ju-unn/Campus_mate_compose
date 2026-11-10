import 'dart:async';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/inquiry/model/data/inquiry_reason.dart';
import 'package:campus_mate/inquiry/model/repository/inquiry_repository.dart';

/// ViewModel · 화면 테스트용 가짜 저장소. 돌려줄 값을 필드로 바꿔 끼운다.
class FakeInquiryRepository implements InquiryRepository {
  Result<void> sendResult = const Success(null);

  final List<({InquiryReason reason, String body, String replyEmail})> sent = [];

  /// 채워 두면 보내기가 이것이 끝날 때까지 멈춘다 — 진행 중에 한 번 더 누르는 상황용.
  Completer<void>? holdSend;

  @override
  Future<Result<void>> send({
    required InquiryReason reason,
    required String body,
    required String replyEmail,
  }) async {
    sent.add((reason: reason, body: body, replyEmail: replyEmail));
    await holdSend?.future;
    return sendResult;
  }
}
