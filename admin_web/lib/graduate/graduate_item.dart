/// 졸업생 검수(A10) 데이터. 서버 모양은 backend/app/admin/graduate_review.py 의 `_summary` · `_detail`.
/// 사진 · 글자 인식 값 · 이전 학교 메일은 대기 건에만 있고, 결정된 건은 이 칸들이 null(서버가 결정 즉시 지운다).
library;

/// 신청 상태(DB graduate_verification_requests.status)
enum GraduateStatus {
  pending('pending', '대기'),
  approved('approved', '승인'),
  rejected('rejected', '반려'),
  cancelled('cancelled', '자동 취소');

  const GraduateStatus(this.code, this.historyLabel);

  final String code;

  /// 지난 신청 줄 글자
  final String historyLabel;

  static GraduateStatus? fromCode(Object? code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }
}

/// 반려 사유 4개(DB check · 서버 RejectReason). 글자는 D10 확정(10-19)이고 backend/app/admin/graduate_notice.py REASON_TEXT 와 같아야 한다
/// (신청자가 받는 알림 문구와 같은 글자, 계획서 D10 — test/graduate/graduate_item_test.dart 가 파일을 읽어 맞춰 본다).
enum GraduateRejectReason {
  unreadable('unreadable', '사진이 잘 안 보여요'),
  notCertificate('not_certificate', '졸업증명서가 아니에요'),
  unverifiable('unverifiable', '확인할 수 없는 번호예요'),
  schoolUnsupported('school_unsupported', '아직 지원하지 않는 학교예요');

  const GraduateRejectReason(this.code, this.label);

  final String code;
  final String label;

  static GraduateRejectReason? fromCode(Object? code) {
    for (final reason in values) {
      if (reason.code == code) return reason;
    }
    return null;
  }
}

enum GraduateOcrState {
  read('read'),
  nothingFound('nothing_found'),
  failed('failed');

  const GraduateOcrState(this.code);

  final String code;

  static GraduateOcrState? fromCode(Object? code) {
    for (final state in values) {
      if (state.code == code) return state;
    }
    return null;
  }
}

/// 중복 경고 3종(서버 `_warnings`). 모르는 코드는 버리지 않고 [other] — 경고를 가리지 않는다.
enum GraduateWarningCode {
  schoolEmailInUse('school_email_in_use', '이 학교 메일은 이미 다른 계정이 쓰고 있어요'),
  schoolEmailRejoinBlocked('school_email_rejoin_blocked', '이 학교 메일은 탈퇴 뒤 재가입이 제한된 메일이에요'),
  documentSeen('document_seen', '같은 문서확인번호로 이미 승인된 다른 계정이 있어요'),
  other('', '확인이 필요한 중복 경고가 있어요');

  const GraduateWarningCode(this.code, this.message);

  final String code;
  final String message;

  static GraduateWarningCode fromCode(Object? code) {
    for (final warning in values) {
      if (warning.code == code && warning != other) return warning;
    }
    return other;
  }
}

/// 승인 · 반려 409 의 이유 6개(서버 CONFLICTS). `already_reviewed` 는 [AdminApi] 가 AlreadyReviewed 로 던져 컨트롤러가
/// 대화상자로 알리고, 나머지 5개는 카드 안 오류 줄에 이 문구로 보인다.
enum GraduateConflict {
  alreadyReviewed('already_reviewed', '다른 관리자가 먼저 처리했어요. 목록을 새로 불러올게요.'),
  alreadyVerified('already_verified', '이미 인증을 마친 계정이라 승인할 수 없어요.'),
  accountWithdrawn('account_withdrawn', '탈퇴한 계정이라 처리할 수 없어요.'),
  documentReused('document_reused', '이미 다른 계정에 쓴 문서확인번호예요. 번호를 다시 확인해 주세요.'),
  studentReused('student_reused', '이미 다른 계정에 쓴 학번이에요. 학번을 다시 확인해 주세요.'),
  rejoinBlocked('rejoin_blocked', '탈퇴 뒤 다시 가입할 수 없는 기간이라 승인할 수 없어요.');

  const GraduateConflict(this.code, this.message);

  final String code;
  final String message;

  static GraduateConflict? fromCode(String? code) {
    for (final conflict in values) {
      if (conflict.code == code) return conflict;
    }
    return null;
  }
}

String? _text(Object? value) => value is String && value.isNotEmpty ? value : null;

/// 문서확인번호 정규화(서버 graduate_verification/hashing.py `normalize_document_number` 와 같은 규칙):
/// 공백 · 하이픈을 떼고 대문자, 영숫자 4~40자가 아니면 null.
String? normalizeDocumentNumber(String raw) => _normalize(raw, _document);

/// 학번 정규화(서버 `normalize_student_number`): 같은 방식, 영숫자 1~20자.
String? normalizeStudentNumber(String raw) => _normalize(raw, _student);

final RegExp _document = RegExp(r'^[A-Z0-9]{4,40}$');
final RegExp _student = RegExp(r'^[A-Z0-9]{1,20}$');

String? _normalize(String raw, RegExp pattern) {
  final text = raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  return pattern.hasMatch(text) ? text : null;
}

/// 입력 칸 아래 안내(정규화 규칙을 미리 알린다). 숫자는 위 정규식과 같다.
const String documentNumberGuide = '공백 · 하이픈은 빼고 영문은 대문자로 맞춰 확인해요. 영문 · 숫자 4~40자';
const String studentNumberGuide = '서류에 학번이 찍혀 있을 때만 적어요. 공백 · 하이픈은 빼고 영문 · 숫자 1~20자';

/// 서버가 받는 입력 상한(원문 기준, 정규화 전 — 서버 pydantic max_length)
const int documentNumberMaxChars = 40;
const int studentNumberMaxChars = 20;

/// 목록 한 줄 — 사진 · 글자 인식이 없는 요약(닉네임 · 학교 이름은 있다).
class GraduateItem {
  const GraduateItem({
    required this.id,
    required this.status,
    required this.reason,
    required this.createdAt,
    required this.decidedAt,
    required this.attemptNo,
    required this.profileId,
    this.nickname,
    this.universityName,
  });

  final String id;
  final GraduateStatus status;
  final GraduateRejectReason? reason;
  final DateTime createdAt;
  final DateTime? decidedAt;

  /// 그 사람의 몇 번째 신청인가(1부터)
  final int attemptNo;
  final String profileId;

  /// 탈퇴한 계정이면 둘 다 null(서버가 가린다). 칸이 없는 옛 응답도 null 로 읽는다.
  final String? nickname;
  final String? universityName;

  static GraduateItem fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'status': final String statusCode,
      'created_at': final String createdAt,
      'attempt_no': final int attemptNo,
      'profile_id': final String profileId,
    }) {
      final status = GraduateStatus.fromCode(statusCode);
      final at = DateTime.tryParse(createdAt);
      final decided = json['decided_at'];
      if (status != null && at != null) {
        return GraduateItem(
          id: id,
          status: status,
          reason: GraduateRejectReason.fromCode(json['reason']),
          createdAt: at,
          decidedAt: decided is String ? DateTime.tryParse(decided) : null,
          attemptNo: attemptNo,
          profileId: profileId,
          nickname: _text(json['nickname']),
          universityName: _text(json['university_name']),
        );
      }
    }
    throw const FormatException('졸업생 신청 한 줄의 모양이 아니에요');
  }
}

/// 글자 인식 결과 — 미리 채우기 힌트일 뿐이다(자동 승인에 쓰지 않는다).
class GraduateOcr {
  const GraduateOcr({
    required this.state,
    required this.documentNumber,
    required this.schoolText,
    required this.suggestedUniversityIds,
  });

  final GraduateOcrState state;
  final String? documentNumber;
  final String? schoolText;
  final List<String> suggestedUniversityIds;

  static GraduateOcr fromJson(Object? json) {
    if (json case {'state': final String stateCode, 'suggested_university_ids': final List<Object?> ids}) {
      final state = GraduateOcrState.fromCode(stateCode);
      final number = json['document_number'];
      final school = json['school_text'];
      if (state != null) {
        return GraduateOcr(
          state: state,
          documentNumber: number is String && number.isNotEmpty ? number : null,
          schoolText: school is String && school.isNotEmpty ? school : null,
          suggestedUniversityIds: [for (final id in ids) if (id is String) id],
        );
      }
    }
    throw const FormatException('글자 인식 결과의 모양이 아니에요');
  }
}

class GraduateWarning {
  const GraduateWarning({required this.code});

  final GraduateWarningCode code;

  static GraduateWarning fromJson(Object? json) {
    if (json case {'code': final Object? code}) return GraduateWarning(code: GraduateWarningCode.fromCode(code));
    throw const FormatException('중복 경고의 모양이 아니에요');
  }
}

/// 같은 사람의 다른 신청 하나(결정 · 사유 · 시각만 — 사진 · 평문은 이미 없다)
class GraduateHistory {
  const GraduateHistory({required this.status, required this.reason, required this.decidedAt});

  final GraduateStatus status;
  final GraduateRejectReason? reason;
  final DateTime? decidedAt;

  static GraduateHistory fromJson(Object? json) {
    if (json case {'status': final String statusCode}) {
      final status = GraduateStatus.fromCode(statusCode);
      final decided = json['decided_at'];
      if (status != null) {
        return GraduateHistory(
          status: status,
          reason: GraduateRejectReason.fromCode(json['reason']),
          decidedAt: decided is String ? DateTime.tryParse(decided) : null,
        );
      }
    }
    throw const FormatException('지난 신청의 모양이 아니에요');
  }
}

/// 한 건 — 요약 + 5분 서명 사진 + 글자 인식 + 이전 학교 메일 + 경고 + 지난 신청.
class GraduateDetail {
  const GraduateDetail({
    required this.item,
    required this.photoUrl,
    required this.ocr,
    required this.previousSchoolEmail,
    required this.warnings,
    required this.history,
  });

  final GraduateItem item;

  /// 서명에 실패했거나 결정된 건이면 null("사진 없음")
  final String? photoUrl;
  final GraduateOcr? ocr;
  final String? previousSchoolEmail;
  final List<GraduateWarning> warnings;
  final List<GraduateHistory> history;

  String get id => item.id;
  bool get isPending => item.status == GraduateStatus.pending;

  static GraduateDetail fromJson(Object? json) {
    if (json case {'photo_url': final String? photoUrl, 'warnings': final List<Object?> warnings, 'history': final List<Object?> history}) {
      final ocr = json['ocr'];
      final email = json['previous_school_email'];
      return GraduateDetail(
        item: GraduateItem.fromJson(json),
        photoUrl: photoUrl,
        ocr: ocr == null ? null : GraduateOcr.fromJson(ocr),
        previousSchoolEmail: email is String && email.isNotEmpty ? email : null,
        warnings: [for (final w in warnings) GraduateWarning.fromJson(w)],
        history: [for (final h in history) GraduateHistory.fromJson(h)],
      );
    }
    throw const FormatException('졸업생 신청 한 건의 모양이 아니에요');
  }
}
