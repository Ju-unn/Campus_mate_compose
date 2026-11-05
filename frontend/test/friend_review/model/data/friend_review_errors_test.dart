import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/friend_review/model/data/friend_review_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('서버 거절 문구로 가르는 판별', () {
    test('이미 리뷰를 남겼다(409)는 서버 문구가 글자까지 같을 때만 참이다', () {
      expect(isAlreadyWritten(const ServerRejectedFailure('이미 리뷰를 남겼어요')), isTrue);
      expect(isAlreadyWritten(const ServerRejectedFailure('이미 리뷰를 남겼습니다')), isFalse);
      expect(isAlreadyWritten(const NetworkFailure()), isFalse);
    });

    test('코드를 찾을 수 없다(404)는 서버 문구가 글자까지 같을 때만 참이다', () {
      expect(isFriendCodeNotFound(const ServerRejectedFailure('코드를 찾을 수 없어요')), isTrue);
      expect(isFriendCodeNotFound(const ServerRejectedFailure('리뷰를 찾을 수 없어요')), isFalse);
      expect(isFriendCodeNotFound(const NotFoundFailure()), isFalse);
    });

    test('리뷰가 이미 없다(404)는 서버 문구가 글자까지 같을 때만 참이다', () {
      expect(isReviewGone(const ServerRejectedFailure('리뷰를 찾을 수 없어요')), isTrue);
      expect(isReviewGone(const ServerRejectedFailure('코드를 찾을 수 없어요')), isFalse);
      expect(isReviewGone(const UnknownFailure()), isFalse);
    });

    test('잠시 뒤 다시(429)는 요청 한도 실패일 때만 참이다', () {
      expect(isFriendCodeTryLater(const RateLimitedFailure()), isTrue);
      expect(isFriendCodeTryLater(const ServerRejectedFailure('잠시 후 다시 시도해 주세요.')), isFalse);
    });
  });

  group('friendReviewFailure', () {
    test('429 는 "잠시 후 다시 시도해 주세요." 에러 종류로 바꾼다', () {
      final shown = friendReviewFailure(const RateLimitedFailure('서버가 준 문구'));

      expect(shown, isA<AppErrorFailure>().having((failure) => failure.error, 'error', AppError.friendCodeTryLater));
    });

    test('그 밖의 실패(404 · 409 · 네트워크)는 그대로 돌려준다', () {
      const rejected = ServerRejectedFailure('코드를 찾을 수 없어요');
      const network = NetworkFailure();

      expect(friendReviewFailure(rejected), same(rejected));
      expect(friendReviewFailure(network), same(network));
    });
  });
}
