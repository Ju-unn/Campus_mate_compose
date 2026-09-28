import 'package:campus_mate/billing/model/heart_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('서버 한 줄을 읽는다', () {
    final task = HeartTask.fromJson({
      'task': 'everytime_post',
      'reward_hearts': 50,
      'state': 'rejected',
      'used': 0,
      'limit': 1,
      'reject_reason': 'date_missing',
    });

    expect(task.kind, HeartTaskKind.everytimePost);
    expect(task.rewardHearts, 50);
    expect(task.state, HeartTaskState.rejected);
    expect(task.limit, 1);
    expect(task.rejectReason, HeartTaskRejectReason.dateMissing);
    expect(task.rejectReason!.label, '날짜가 안 보여요');
  });

  test('사유가 없거나 모르는 값이면 null 이다', () {
    expect(HeartTaskRejectReason.tryParse(null), isNull);
    expect(HeartTaskRejectReason.tryParse('blurry'), isNull);
  });

  test('모르는 항목 이름은 읽지 못한다 — ApiClient 가 알 수 없는 오류로 바꾼다', () {
    expect(
      () => HeartTask.fromJson({'task': 'x', 'reward_hearts': 1, 'state': 'open', 'used': 0, 'limit': 1}),
      throwsA(anything),
    );
  });

  test('인증샷을 내는 항목은 둘뿐이다', () {
    expect(HeartTaskKind.values.where((kind) => kind.needsProof), [HeartTaskKind.everytimePost, HeartTaskKind.kakaoShare]);
    expect(HeartTaskKind.tryParse('kakao_share'), HeartTaskKind.kakaoShare);
    expect(HeartTaskKind.tryParse('nope'), isNull);
  });
}
