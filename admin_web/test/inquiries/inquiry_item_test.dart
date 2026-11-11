import 'package:campus_mate_admin/inquiries/inquiry_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/inquiry_fakes.dart';

/// 서버 계약(backend/app/admin/inquiry_review.py `_item` · app/inquiries/reasons.py)의 칸 이름 · 글자 그대로
void main() {
  test('사유 글자는 서버 reasons.py 와 같다', () {
    expect(inquiryReasonLabel('account'), '계정·인증');
    expect(inquiryReasonLabel('payment'), '결제·하트');
    expect(inquiryReasonLabel('matching'), '매칭·카드');
    expect(inquiryReasonLabel('safety'), '신고·안전');
    expect(inquiryReasonLabel('bug'), '앱 오류');
    expect(inquiryReasonLabel('other'), '기타');
    expect(inquiryReasonLabel('new_reason'), 'new_reason'); // 모르는 코드는 그대로
  });

  test('상태 글자: 새 문의 · 처리 중 · 답변 완료, 서버 코드는 new · in_progress · answered', () {
    expect([for (final s in InquiryStatus.values) (s.code, s.label)], [
      ('new', '새 문의'),
      ('in_progress', '처리 중'),
      ('answered', '답변 완료'),
    ]);
    expect(InquiryStatus.fromCode('answered'), InquiryStatus.answered);
    expect(InquiryStatus.fromCode('bogus'), isNull);
  });

  test('한 줄을 읽는다 — 보낸 사람 · 메모 · 시각, 커서용 created_at 원문도 든다', () {
    final item = InquiryItem.fromJson(inquiryRow(inquiryA, adminMemo: '전화 예정', createdAt: '2026-11-10T01:00:00.123456+00:00'));

    expect(item.id, inquiryA);
    expect((item.reason, item.body, item.replyEmail, item.status), ('bug', '앱이 멈춰요', 'me@example.com', InquiryStatus.newInquiry));
    expect(item.adminMemo, '전화 예정');
    expect(item.createdAtRaw, '2026-11-10T01:00:00.123456+00:00');
    expect(item.createdAt, DateTime.utc(2026, 11, 10, 1, 0, 0, 123, 456));
    expect(item.answeredAt, isNull);
    expect(item.writerLabel, '하늘 · 테스트대학교');
  });

  test('탈퇴한 사람의 문의(profile null)는 "탈퇴한 사용자", 닉네임 · 학교가 비면 "—"', () {
    expect(InquiryItem.fromJson(inquiryRow(inquiryA, profile: null)).writerLabel, '탈퇴한 사용자');
    expect(InquiryItem.fromJson(inquiryRow(inquiryA, profile: {'id': 'p', 'nickname': null, 'university': null})).writerLabel, '— · —');
  });

  test('copyWith 없이 새 줄로 바뀐다 — 모양이 틀리면 FormatException', () {
    expect(() => InquiryItem.fromJson({'id': 'x'}), throwsFormatException);
    expect(() => InquiryItem.fromJson(inquiryRow(inquiryA, status: 'bogus')), throwsFormatException);
    expect(() => InquiryItem.fromJson(inquiryRow(inquiryA, createdAt: 'yesterday')), throwsFormatException);
  });
}
