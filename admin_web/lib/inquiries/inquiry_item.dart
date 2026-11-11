/// 문의 관리 데이터. 서버 모양은 backend/app/admin/inquiry_review.py 의 `_item`, 사유 글자는 backend/app/inquiries/reasons.py 의 REASON_LABELS.
/// 사용자가 쓴 글(본문 · 답장 메일 · 닉네임)과 운영자 메모는 손대지 않고 그대로 들고 있다 — 화면은 일반 Text 로만 그린다.
library;

import 'package:campus_mate_admin/reports/report_item.dart' show missingValue;

/// 문의 상태. 서버 코드는 new · in_progress · answered. `new` 는 예약어라 [newInquiry].
enum InquiryStatus {
  newInquiry('new', '새 문의'),
  inProgress('in_progress', '처리 중'),
  answered('answered', '답변 완료');

  const InquiryStatus(this.code, this.label);

  final String code;
  final String label;

  static InquiryStatus? fromCode(String code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }
}

/// 사유 코드 → 글자. 서버 REASON_LABELS 와 같다(메일 제목 · 앱과 한 이름). 모르는 코드는 그대로 보인다.
String inquiryReasonLabel(String code) {
  return switch (code) {
    'account' => '계정·인증',
    'payment' => '결제·하트',
    'matching' => '매칭·카드',
    'safety' => '신고·안전',
    'bug' => '앱 오류',
    'other' => '기타',
    _ => code,
  };
}

/// 문의 한 줄(목록과 처리 응답이 같은 모양).
class InquiryItem {
  const InquiryItem({
    required this.id,
    required this.reason,
    required this.body,
    required this.replyEmail,
    required this.status,
    required this.adminMemo,
    required this.createdAt,
    required this.createdAtRaw,
    required this.answeredAt,
    required this.nickname,
    required this.university,
    required this.hasWriter,
  });

  final String id;
  final String reason;
  final String body;
  final String replyEmail;
  final InquiryStatus status;
  final String? adminMemo;
  final DateTime createdAt;

  /// 서버가 준 created_at 글자 그대로 — 다음 쪽 커서(before)는 이 글자로 보낸다(다시 만든 글자는 마이크로초가 달라질 수 있다).
  final String createdAtRaw;
  final DateTime? answeredAt;
  final String? nickname;
  final String? university;

  /// 탈퇴한 사람의 문의면 거짓(서버 profile 이 null)
  final bool hasWriter;

  /// "보낸 사람" 칸: "닉네임 · 학교". 탈퇴한 사람은 "탈퇴한 사용자".
  String get writerLabel => hasWriter ? '${nickname ?? missingValue} · ${university ?? missingValue}' : '탈퇴한 사용자';

  /// 목록 "내용" 칸 — 첫 줄만
  String get firstLine => body.split('\n').first;

  static InquiryItem fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'reason': final String reason,
      'body': final String body,
      'reply_email': final String replyEmail,
      'status': final String status,
      'created_at': final String createdAtRaw,
    }) {
      final state = InquiryStatus.fromCode(status);
      final created = DateTime.tryParse(createdAtRaw);
      final memo = json['admin_memo'];
      final answered = json['answered_at'];
      final profile = json['profile'];
      if (state != null && created != null && memo is String? && answered is String? && (profile == null || profile is Map)) {
        final nickname = profile is Map ? profile['nickname'] : null;
        final university = profile is Map ? profile['university'] : null;
        return InquiryItem(
          id: id,
          reason: reason,
          body: body,
          replyEmail: replyEmail,
          status: state,
          adminMemo: memo,
          createdAt: created,
          createdAtRaw: createdAtRaw,
          answeredAt: answered == null ? null : DateTime.tryParse(answered),
          nickname: nickname is String ? nickname : null,
          university: university is String ? university : null,
          hasWriter: profile != null,
        );
      }
    }
    throw const FormatException('문의 한 줄의 모양이 아니에요');
  }
}
