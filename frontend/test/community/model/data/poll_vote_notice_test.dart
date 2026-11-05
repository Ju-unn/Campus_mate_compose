import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/data/poll_vote_notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('보상 알림은 실패 없이 보상이다', () {
    const notice = PollVoteNotice.reward();

    expect(notice.isReward, isTrue);
    expect(notice.failure, isNull);
  });

  test('실패 알림은 보상이 아니고 실패 종류를 그대로 든다', () {
    const failure = NetworkFailure();
    const notice = PollVoteNotice.failed(failure);

    expect(notice.isReward, isFalse);
    expect(notice.failure, same(failure));
  });
}
