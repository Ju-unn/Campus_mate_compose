import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/safety/model/data/safety_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('중복 신고 409 를 알아본다', () {
    expect(isAlreadyReported(const ServerRejectedFailure('이미 신고를 완료했어요')), isTrue);
    // 옛 문구("…사용자예요")는 리뷰 · 투표 글 · 메시지 신고에도 나와 어색해 바꿨다(사용자 10-04) — 서버와 같이 바뀐다.
    expect(isAlreadyReported(const ServerRejectedFailure('이미 신고한 사용자예요')), isFalse);
    expect(isAlreadyReported(const ServerRejectedFailure('프로필을 찾을 수 없어요')), isFalse);
    expect(isAlreadyReported(const NetworkFailure()), isFalse);
  });

  test('신고 대상이 사라진 404 를 알아본다', () {
    expect(isReportTargetGone(const ServerRejectedFailure('프로필을 찾을 수 없어요')), isTrue);
    expect(isReportTargetGone(const ServerRejectedFailure('메시지를 찾을 수 없어요')), isTrue);
    expect(isReportTargetGone(const ServerRejectedFailure('이미 신고를 완료했어요')), isFalse);
  });

  test('신고하려던 투표 글이 사라진 404 도 알아본다 — 시트를 닫는다(A16 · 서버 POLL_NOT_FOUND)', () {
    expect(isReportTargetGone(const ServerRejectedFailure('질문을 찾을 수 없어요')), isTrue);
  });

  test('상대 프로필 404 만 프로필이 사라진 것으로 알아본다', () {
    expect(isProfileGone(const ServerRejectedFailure('프로필을 찾을 수 없어요')), isTrue);
    expect(isProfileGone(const ServerRejectedFailure('메시지를 찾을 수 없어요')), isFalse);
    expect(isProfileGone(const NetworkFailure()), isFalse);
  });

  test('신고 실패: 상한은 신고 말 종류로 바꾸고 나머지는 그 실패 그대로', () {
    expect(
      reportFailure(const RateLimitedFailure()),
      isA<AppErrorFailure>().having((failure) => failure.error, 'error', AppError.reportLimited),
    );
    const rejected = ServerRejectedFailure('이미 신고를 완료했어요');
    const network = NetworkFailure();
    expect(reportFailure(rejected), same(rejected));
    expect(reportFailure(network), same(network));
  });
}
