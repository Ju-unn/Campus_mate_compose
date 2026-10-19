import 'package:campus_mate_admin/heart_tasks/heart_task_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/heart_task_fakes.dart';

void main() {
  test('목록 한 줄은 사진 없는 요약이다: 번호 · 항목 · 닉네임 · 학교 · 보상 · 제출 시각', () {
    final item = HeartTaskItem.fromJson(taskRow('s1', task: 'kakao_share', nickname: '하늘', university: '테스트대학교'));

    expect(item.id, 's1');
    expect(item.kind, HeartTaskKind.kakaoShare);
    expect(item.nickname, '하늘');
    expect(item.university, '테스트대학교');
    expect(item.rewardHearts, 40);
    expect(item.createdAt, DateTime.utc(2026, 10, 18, 5, 8));
  });

  test('한 건: 사진이 없으면(60일 정리 · 서명 실패) null, 지난 제출이 없으면 빈 목록', () {
    final detail = HeartTaskDetail.fromJson({...taskRow('s1'), 'photo_url': null, 'previous': <Object?>[]});

    expect(detail.item.id, 's1');
    expect(detail.isWaiting, isTrue);
    expect(detail.photoUrl, isNull);
    expect(detail.previous, isEmpty);
  });

  test('한 건: 지난 제출은 번호 · 상태 · 사진 주소(없으면 null)', () {
    final detail = HeartTaskDetail.fromJson({
      ...taskRow('s1'),
      'status': 'approved',
      'photo_url': 'https://storage.test/s1.jpg',
      'previous': [previousPhoto('old1'), previousPhoto('old2', status: 'rejected', photo: false)],
    });

    expect(detail.isWaiting, isFalse);
    expect(detail.photoUrl, 'https://storage.test/s1.jpg');
    expect(detail.previous.map((p) => (p.id, p.status, p.photoUrl)), [
      ('old1', 'approved', 'https://storage.test/old1.jpg?token=t'),
      ('old2', 'rejected', null),
    ]);
    expect(detail.previous.first.createdAt, DateTime.utc(2026, 10, 11, 5));
  });

  test('HeartTaskDetail parses photo_urls in order and keeps nulls', () {
    final detail = HeartTaskDetail.fromJson({
      ...taskRow('s1'),
      'photo_url': 'https://storage.test/a.jpg',
      'photo_urls': ['https://storage.test/a.jpg', null, 'https://storage.test/c.jpg'],
      'previous': <Object?>[],
    });

    expect(detail.photoUrls, ['https://storage.test/a.jpg', null, 'https://storage.test/c.jpg']);
    expect(detail.photoUrl, 'https://storage.test/a.jpg', reason: '옛 getter 는 첫 장');
  });

  test('photo_urls wins over the legacy photo_url, and a null first photo stays null', () {
    final detail = HeartTaskDetail.fromJson({
      ...taskRow('s1'),
      'photo_url': 'https://storage.test/old.jpg',
      'photo_urls': [null, 'https://storage.test/b.jpg'],
      'previous': <Object?>[],
    });

    expect(detail.photoUrls, [null, 'https://storage.test/b.jpg']);
    expect(detail.photoUrl, isNull);
  });

  test('falls back to a one-item list from the legacy photo_url (옛 서버)', () {
    final detail = HeartTaskDetail.fromJson({
      ...taskRow('s1'),
      'photo_url': 'https://storage.test/a.jpg',
      'previous': <Object?>[],
    });

    expect(detail.photoUrls, ['https://storage.test/a.jpg']);
  });

  test('photo_url null and photo_urls absent gives an empty list; an empty photo_urls stays empty', () {
    final legacy = HeartTaskDetail.fromJson({...taskRow('s1'), 'photo_url': null, 'previous': <Object?>[]});
    final cleaned = HeartTaskDetail.fromJson({...taskRow('s1'), 'photo_url': null, 'photo_urls': <Object?>[], 'previous': <Object?>[]});

    expect(legacy.photoUrls, isEmpty);
    expect(cleaned.photoUrls, isEmpty);
    expect(cleaned.photoUrl, isNull);
  });

  test('photo_urls must be a list of strings or nulls; with neither photo field the row is malformed', () {
    expect(() => HeartTaskDetail.fromJson({...taskRow('s1'), 'photo_urls': 'x', 'previous': <Object?>[]}), throwsFormatException);
    expect(() => HeartTaskDetail.fromJson({...taskRow('s1'), 'photo_urls': [1], 'previous': <Object?>[]}), throwsFormatException);
    expect(() => HeartTaskDetail.fromJson({...taskRow('s1'), 'previous': <Object?>[]}), throwsFormatException);
  });

  test('지난 제출도 photo_urls 를 읽고, 없으면 옛 photo_url 하나짜리 목록', () {
    final detail = HeartTaskDetail.fromJson({
      ...taskRow('s1'),
      'photo_url': null,
      'previous': [
        {...previousPhoto('n1'), 'photo_urls': ['https://storage.test/n1.jpg', null]},
        previousPhoto('l1', legacy: true),
        previousPhoto('l2', legacy: true, photo: false),
      ],
    });

    expect(detail.previous.map((p) => p.photoUrls), [
      ['https://storage.test/n1.jpg', null],
      ['https://storage.test/l1.jpg?token=t'],
      isEmpty,
    ]);
    expect(detail.previous.map((p) => p.photoUrl), ['https://storage.test/n1.jpg', 'https://storage.test/l1.jpg?token=t', isNull]);
  });

  test('지난 제출 줄의 사진은 비어 있지 않은 첫 장 — 첫 장 서명이 실패해도 다른 장이 있으면 그것, 모두 없을 때만 null', () {
    final detail = HeartTaskDetail.fromJson({
      ...taskRow('s1'),
      'photo_url': null,
      'previous': [
        {...previousPhoto('p1'), 'photo_urls': [null, 'https://storage.test/p1b.jpg', 'https://storage.test/p1c.jpg']},
        {...previousPhoto('p2'), 'photo_urls': [null, null]},
      ],
    });

    expect(detail.previous.map((p) => p.photoUrl), ['https://storage.test/p1b.jpg', isNull]);
    expect(detail.previous.first.photoIndex, 1);
    expect(detail.previous.last.photoIndex, isNull);
  });

  test('모르는 항목 · 빠진 칸 · 틀린 시각이면 FormatException', () {
    expect(() => HeartTaskItem.fromJson(taskRow('s1', task: 'instagram')), throwsFormatException);
    expect(() => HeartTaskItem.fromJson({...taskRow('s1')}..remove('profile')), throwsFormatException);
    expect(() => HeartTaskItem.fromJson(taskRow('s1', createdAt: '어제')), throwsFormatException);
    expect(() => HeartTaskDetail.fromJson(taskRow('s1')), throwsFormatException);
  });

  test('닉네임이 비어 있으면 줄표로 보인다', () {
    expect(HeartTaskItem.fromJson(taskRow('s1', nickname: null)).nickname, '—');
  });

  test('항목 이름: 목록은 에브리타임 · 단톡방, 정보 카드는 에브리타임 홍보 · 단톡방 공유', () {
    expect(HeartTaskKind.everytimePost.code, 'everytime_post');
    expect(HeartTaskKind.kakaoShare.code, 'kakao_share');
    expect(HeartTaskKind.values.map((k) => k.listLabel), ['에브리타임', '단톡방']);
    expect(HeartTaskKind.values.map((k) => k.infoLabel), ['에브리타임 홍보', '단톡방 공유']);
  });

  test('반려 사유 3개는 서버 값과 앱(heart_task.dart)의 글자 그대로', () {
    expect(HeartTaskRejectReason.values.map((r) => (r.code, r.label)), [
      ('date_missing', '날짜가 안 보여요'),
      ('not_verified', '게시글·공유가 확인되지 않아요'),
      ('reused', '이미 쓴 캡처예요'),
    ]);
  });

  test('제출 시각은 한국 시간 YYYY-MM-DD HH:mm', () {
    expect(formatSubmittedAt(DateTime.utc(2026, 10, 18, 5, 20)), '2026-10-18 14:20');
    // 한국 날짜가 넘어가는 시각
    expect(formatSubmittedAt(DateTime.utc(2026, 12, 31, 15, 5)), '2027-01-01 00:05');
    expect(formatSubmittedAt(DateTime.parse('2026-03-04T09:07:00+09:00')), '2026-03-04 09:07');
  });

  test('지난 시간: 1시간 안은 n분 전, 하루 안은 n시간 전, 그 뒤는 n일 전', () {
    final now = testNow;
    expect(formatAgo(now.subtract(const Duration(seconds: 30)), now), '0분 전');
    expect(formatAgo(now.subtract(const Duration(minutes: 12)), now), '12분 전');
    expect(formatAgo(now.subtract(const Duration(minutes: 59, seconds: 59)), now), '59분 전');
    expect(formatAgo(now.subtract(const Duration(minutes: 60)), now), '1시간 전');
    expect(formatAgo(now.subtract(const Duration(hours: 23, minutes: 59)), now), '23시간 전');
    expect(formatAgo(now.subtract(const Duration(days: 3, hours: 2)), now), '3일 전');
    // 시계가 조금 어긋나 미래 시각이 와도 음수를 쓰지 않는다
    expect(formatAgo(now.add(const Duration(minutes: 2)), now), '0분 전');
  });

  test('보상은 "하트 {n}개"', () {
    expect(formatReward(40), '하트 40개');
  });
}
