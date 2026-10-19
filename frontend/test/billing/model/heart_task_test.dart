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

  test('새 칸 — 검수 대기 줄과 서명 주소(실패한 장은 null)를 읽는다', () {
    final task = HeartTask.fromJson({
      'task': 'kakao_share',
      'reward_hearts': 25,
      'state': 'reviewing',
      'used': 1,
      'limit': 3,
      'reject_reason': null,
      'can_submit': true,
      'max_photos': 3,
      'pending': [
        {
          'id': 's1',
          'created_at': '2026-10-19T01:00:00+00:00',
          'photo_urls': ['u1', null, 'u3'],
        },
      ],
    });

    expect(task.canSubmit, isTrue);
    expect(task.maxPhotos, 3);
    expect(task.state, HeartTaskState.reviewing);
    expect(task.pending.single.id, 's1');
    expect(task.pending.single.createdAt, DateTime.utc(2026, 10, 19, 1));
    expect(task.pending.single.photoUrls, ['u1', null, 'u3']);
  });

  test('옛 서버 응답(새 칸 없음)도 읽는다 — 사진은 한 장까지, 낼 수 있는지는 state 로 안다', () {
    HeartTask read(String code, String state) => HeartTask.fromJson(
        {'task': code, 'reward_hearts': 25, 'state': state, 'used': 0, 'limit': 3, 'reject_reason': null});

    expect([for (final s in ['open', 'rejected', 'reviewing', 'done']) read('kakao_share', s).canSubmit],
        [true, true, false, false]);
    expect(read('kakao_share', 'open').maxPhotos, 1);
    expect(read('kakao_share', 'open').pending, isEmpty);
    // 투표는 인증샷을 내지 않는다.
    expect((read('poll_vote', 'open').canSubmit, read('poll_vote', 'open').maxPhotos), (false, 0));
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
