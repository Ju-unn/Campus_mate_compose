import 'dart:io';

import 'package:campus_mate_admin/graduate/graduate_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/graduate_fakes.dart';

void main() {
  group('목록 한 줄 파싱', () {
    test('서버 요약 모양을 읽는다', () {
      final item = GraduateItem.fromJson(graduateRow('g1', attemptNo: 2));

      expect(item.id, 'g1');
      expect(item.status, GraduateStatus.pending);
      expect(item.attemptNo, 2);
      expect(item.createdAt, DateTime.utc(2026, 10, 19, 2, 20));
      expect(item.decidedAt, isNull);
      expect(item.reason, isNull);
      expect(item.nickname, '닉네임A');
      expect(item.universityName, '서울대학교');
    });

    test('닉네임 · 학교 이름이 null 이거나 칸이 아예 없어도 읽는다(탈퇴 계정 · 옛 서버)', () {
      final withdrawn = GraduateItem.fromJson(graduateRow('g1', nickname: null, universityName: null));
      final old = GraduateItem.fromJson({...graduateRow('g1')}..remove('nickname')..remove('university_name'));

      for (final item in [withdrawn, old]) {
        expect(item.nickname, isNull);
        expect(item.universityName, isNull);
        expect(item.id, 'g1');
      }
    });

    test('빈 글자는 없는 것으로 본다', () {
      final item = GraduateItem.fromJson(graduateRow('g1', nickname: '', universityName: ''));

      expect(item.nickname, isNull);
      expect(item.universityName, isNull);
    });

    test('모양이 틀리면 FormatException', () {
      expect(() => GraduateItem.fromJson({'id': 'g1'}), throwsFormatException);
      expect(() => GraduateItem.fromJson({...graduateRow('g1'), 'status': 'weird'}), throwsFormatException);
      expect(() => GraduateItem.fromJson({...graduateRow('g1'), 'created_at': 'not a date'}), throwsFormatException);
    });
  });

  group('한 건 파싱', () {
    Map<String, Object?> pendingDetail() => {
      ...graduateRow('g1'),
      'photo_url': 'https://storage.test/g1.jpg',
      'ocr': {'state': 'read', 'document_number': 'A12B-3456-78CD', 'school_text': '서울대학교', 'suggested_university_ids': ['u-snu']},
      'previous_school_email': 'hong@snu.ac.kr',
      'warnings': [
        graduateWarning('school_email_in_use', profileId: 'p-9', profileStatus: 'active'),
        graduateWarning('school_email_rejoin_blocked'),
        graduateWarning('document_seen', profileId: 'p-8'),
      ],
      'history': [graduateHistory('rejected', reason: 'not_certificate'), graduateHistory('cancelled')],
    };

    test('대기 건: 사진 · 글자 인식 · 이전 메일 · 경고 3종 · 이력', () {
      final detail = GraduateDetail.fromJson(pendingDetail());

      expect(detail.item.id, 'g1');
      expect(detail.isPending, isTrue);
      expect(detail.photoUrl, 'https://storage.test/g1.jpg');
      expect(detail.ocr?.state, GraduateOcrState.read);
      expect(detail.ocr?.documentNumber, 'A12B-3456-78CD');
      expect(detail.ocr?.schoolText, '서울대학교');
      expect(detail.ocr?.suggestedUniversityIds, ['u-snu']);
      expect(detail.previousSchoolEmail, 'hong@snu.ac.kr');
      expect(detail.warnings.map((w) => w.code), [
        GraduateWarningCode.schoolEmailInUse,
        GraduateWarningCode.schoolEmailRejoinBlocked,
        GraduateWarningCode.documentSeen,
      ]);
      expect(detail.history.map((h) => (h.status, h.reason)), [
        (GraduateStatus.rejected, GraduateRejectReason.notCertificate),
        (GraduateStatus.cancelled, null),
      ]);
    });

    test('결정된 건: photo_url · ocr · previous_school_email 이 null 이어도 읽는다', () {
      final detail = GraduateDetail.fromJson({
        ...graduateRow('g2'),
        'status': 'approved',
        'decided_at': '2026-10-19T03:00:00+00:00',
        'photo_url': null,
        'ocr': null,
        'previous_school_email': null,
        'warnings': const <Object?>[],
        'history': const <Object?>[],
      });

      expect(detail.isPending, isFalse);
      expect(detail.photoUrl, isNull);
      expect(detail.ocr, isNull);
      expect(detail.previousSchoolEmail, isNull);
      expect(detail.warnings, isEmpty);
    });

    test('글자 인식이 못 읽은 건(nothing_found · failed)도 읽는다', () {
      for (final (code, state) in [('nothing_found', GraduateOcrState.nothingFound), ('failed', GraduateOcrState.failed)]) {
        final detail = GraduateDetail.fromJson({
          ...pendingDetail(),
          'ocr': {'state': code, 'document_number': null, 'school_text': null, 'suggested_university_ids': const <Object?>[]},
        });
        expect(detail.ocr?.state, state);
        expect(detail.ocr?.documentNumber, isNull);
      }
    });

    test('모르는 경고 코드는 버리지 않고 "그 밖의 경고"로 보인다', () {
      final detail = GraduateDetail.fromJson({
        ...pendingDetail(),
        'warnings': [graduateWarning('brand_new_code')],
      });

      expect(detail.warnings.single.code, GraduateWarningCode.other);
    });

    test('필수 칸이 빠지면 FormatException', () {
      final broken = {...pendingDetail()}..remove('warnings');
      expect(() => GraduateDetail.fromJson(broken), throwsFormatException);
    });
  });

  group('반려 사유 · 이전 이력 글자', () {
    test('코드 4개와 문구(D10)', () {
      expect({for (final r in GraduateRejectReason.values) r.code: r.label}, {
        'unreadable': '사진이 잘 안 보여요',
        'not_certificate': '졸업증명서가 아니에요',
        'unverifiable': '확인할 수 없는 번호예요',
        'school_unsupported': '아직 지원하지 않는 학교예요',
      });
    });

    // 서버가 신청자에게 보내는 문구와 한 글자도 다르면 안 된다(앱 · 푸시 · 관리자 웹이 같은 글자, D10)
    final server = File('../backend/app/admin/graduate_notice.py');
    test('서버 알림 문구(graduate_notice.py REASON_TEXT)와 같은 글자', () {
      final source = server.readAsStringSync();
      final found = {for (final m in RegExp(r'"(\w+)":\s*"([^"]+)"').allMatches(source)) m.group(1)!: m.group(2)!};

      for (final reason in GraduateRejectReason.values) {
        expect(found[reason.code], reason.label, reason: reason.code);
      }
    }, skip: server.existsSync() ? false : 'backend 폴더가 없다');

    test('이력 한 줄 글자: 승인 · 반려 · 자동 취소 · 대기', () {
      expect(GraduateStatus.approved.historyLabel, '승인');
      expect(GraduateStatus.rejected.historyLabel, '반려');
      expect(GraduateStatus.cancelled.historyLabel, '자동 취소');
      expect(GraduateStatus.pending.historyLabel, '대기');
    });
  });

  group('번호 정규화 안내와 같은 규칙(서버 hashing.py)', () {
    test('문서확인번호: 공백 · 하이픈을 떼고 대문자, 영숫자 4~40자만', () {
      expect(normalizeDocumentNumber('a12b-3456 78cd'), 'A12B345678CD');
      expect(normalizeDocumentNumber('ABCD'), 'ABCD');
      expect(normalizeDocumentNumber('AB1'), isNull);
      expect(normalizeDocumentNumber('A' * 40), 'A' * 40);
      expect(normalizeDocumentNumber('A' * 41), isNull);
      expect(normalizeDocumentNumber('가나다라마'), isNull);
      expect(normalizeDocumentNumber('   '), isNull);
    });

    test('학번: 공백 · 하이픈을 떼고 대문자, 영숫자 1~20자만', () {
      expect(normalizeStudentNumber('20-21 0001'), '20210001');
      expect(normalizeStudentNumber('a'), 'A');
      expect(normalizeStudentNumber('1' * 20), '1' * 20);
      expect(normalizeStudentNumber('1' * 21), isNull);
      expect(normalizeStudentNumber(''), isNull);
      expect(normalizeStudentNumber('학번'), isNull);
    });

    test('안내 글자는 규칙 숫자와 같다', () {
      expect(documentNumberGuide, '공백 · 하이픈은 빼고 영문은 대문자로 맞춰 확인해요. 영문 · 숫자 4~40자');
      expect(studentNumberGuide, '서류에 학번이 찍혀 있을 때만 적어요. 공백 · 하이픈은 빼고 영문 · 숫자 1~20자');
    });
  });

  group('409 이유 6종 한국어 문구', () {
    test('이유 코드마다 문구가 있고 서로 다르다', () {
      expect(GraduateConflict.fromCode('already_verified')?.message, '이미 인증을 마친 계정이라 승인할 수 없어요.');
      expect(GraduateConflict.fromCode('account_withdrawn')?.message, '탈퇴한 계정이라 처리할 수 없어요.');
      expect(GraduateConflict.fromCode('document_reused')?.message, '이미 다른 계정에 쓴 문서확인번호예요. 번호를 다시 확인해 주세요.');
      expect(GraduateConflict.fromCode('student_reused')?.message, '이미 다른 계정에 쓴 학번이에요. 학번을 다시 확인해 주세요.');
      expect(GraduateConflict.fromCode('rejoin_blocked')?.message, '탈퇴 뒤 다시 가입할 수 없는 기간이라 승인할 수 없어요.');
      expect(GraduateConflict.fromCode('already_reviewed')?.message, '다른 관리자가 먼저 처리했어요. 목록을 새로 불러올게요.');
      expect(GraduateConflict.values.map((c) => c.message).toSet(), hasLength(6));
      expect(GraduateConflict.fromCode('nope'), isNull);
      expect(GraduateConflict.fromCode(null), isNull);
    });
  });
}
