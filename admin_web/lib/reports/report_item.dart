/// 신고 검수(A4) 데이터. 서버 모양은 backend/app/admin/report_review.py 의 `_summary` · `detail` · chat-context.
/// 서버 글자(닉네임 · 사본 · 채팅)는 손대지 않고 그대로 들고 있다 — 화면은 일반 Text 로만 그린다.
library;

/// 신고 대상 종류. 글자는 pen 자리마다 다르다 — 목록 칩 · 표는 "친구 리뷰", 상세는 "지인 리뷰"(A4 PNG 그대로).
enum ReportTargetType {
  profile('profile', '프로필', '프로필 신고', '신고 당시 사본 · 프로필'),
  message('message', '메시지', '메시지 신고', '신고 당시 사본'),
  friendReview('friend_review', '친구 리뷰', '지인 리뷰 신고', '신고 당시 사본 · 지인 리뷰'),
  poll('poll', '투표', '투표 글 신고', '신고 당시 사본 · 투표 글');

  const ReportTargetType(this.code, this.listLabel, this.detailTitle, this.copyTitle);

  final String code;
  final String listLabel;
  final String detailTitle;
  final String copyTitle;

  /// 투표 글 · 지인 리뷰 — 글 가림 / 해제가 있는 종류
  bool get isContent => this == poll || this == friendReview;

  static ReportTargetType? fromCode(String code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

/// 신고 상태. 칩 · 다른 신고 줄은 "열림", 배지는 "대기"(pen ⑤ · 목록 PNG).
enum ReportStatus {
  open('open', '열림', '대기'),
  actioned('actioned', '조치', '조치'),
  dismissed('dismissed', '기각', '기각');

  const ReportStatus(this.code, this.label, this.badgeLabel);

  final String code;
  final String label;
  final String badgeLabel;

  static ReportStatus? fromCode(String code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }
}

/// 투표 글 · 지인 리뷰의 지금 상태(content_status)
enum ContentStatus { visible, blinded }

/// 사람 조치(POST /admin/profiles/{id}/{action})
enum ProfileAction { suspend, unsuspend, unhide }

/// 신고 사유 코드 → 글자. 앱 신고 시트(pen yl8gX · frontend report_reason.dart)와 같은 짧은 글자 — 표 칸 170 에 들어간다.
/// 모르는 코드는 그대로 보인다.
String reportReasonLabel(String code) {
  return switch (code) {
    'abuse' => '욕설·비방·혐오',
    'sexual' => '성적 불쾌감',
    'spam' => '광고·스팸',
    'fake' => '사칭·허위',
    'other' => '기타',
    _ => code,
  };
}

/// 값이 없을 때(탈퇴 · 가입 전 · 목록 응답에 없는 칸)
const String missingValue = '—';

/// 신고당한 사람(target_profile). 탈퇴로 지워졌으면 신고 쪽이 null 을 든다.
class ReportTarget {
  const ReportTarget({required this.id, required this.nickname, required this.university, required this.status, required this.autoHiddenAt});

  final String id;

  /// 가입을 마치기 전이면 null
  final String? nickname;
  final String university;

  /// profiles.status — pending · active · suspended · withdrawn
  final String status;
  final DateTime? autoHiddenAt;

  bool get isSuspended => status == 'suspended';
  bool get isAutoHidden => autoHiddenAt != null;

  /// 정지할 수 있는 상태(DB 함수가 pending · active 만 정지한다)
  bool get canSuspend => status == 'active' || status == 'pending';

  String get displayName => nickname ?? missingValue;

  /// 대상 요약의 "상태" 값(pen: 정상 · 정지 중 · 정상 · 자동 가림 중). 가입 중 · 탈퇴는 pen 에 없는 값.
  String get statusLabel {
    final base = switch (status) {
      'active' => '정상',
      'suspended' => '정지 중',
      'pending' => '가입 중',
      'withdrawn' => '탈퇴',
      _ => status,
    };
    return isAutoHidden ? '$base · 자동 가림 중' : base;
  }

  static ReportTarget? fromJson(Object? json) {
    if (json == null) return null;
    if (json case {
      'id': final String id,
      'nickname': final String? nickname,
      'university': final String university,
      'status': final String status,
      'auto_hidden_at': final String? hiddenAt,
    }) {
      return ReportTarget(
        id: id,
        nickname: nickname,
        university: university,
        status: status,
        autoHiddenAt: hiddenAt == null ? null : DateTime.tryParse(hiddenAt),
      );
    }
    throw const FormatException('신고 대상의 모양이 아니에요');
  }
}

/// 목록 한 줄(_summary). 사본 · 사진은 없다(신고자 수 · 투표 질문 앞부분은 있다) — 줄을 고르면 [ReportDetail].
class ReportSummary {
  const ReportSummary({
    required this.id,
    required this.type,
    required this.targetId,
    required this.reason,
    required this.reasonNote,
    required this.status,
    required this.createdAt,
    required this.resolvedAt,
    required this.target,
    this.openReporters,
    this.preview,
  });

  final String id;
  final ReportTargetType type;

  /// 신고된 것(프로필 · 메시지 · 리뷰 · 투표 글)의 번호 — 글 가림 경로에 쓴다
  final String targetId;
  final String reason;
  final String? reasonNote;
  final ReportStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final ReportTarget? target;

  /// 같은 대상의 열린 신고의 서로 다른 신고자 수(서버 open_reporters). 칸이 없는 옛 응답이면 null.
  final int? openReporters;

  /// 투표 글 신고의 질문 앞부분(서버 preview). 다른 종류는 서버가 보내지 않는다.
  final String? preview;

  bool get isOpen => status == ReportStatus.open;

  /// 표의 "대상 요약". 투표 글은 질문 앞부분(preview)이 먼저, 없으면 닉네임으로 쓴다.
  String get targetSummary {
    final preview = this.preview?.trim();
    if (type == ReportTargetType.poll && preview != null && preview.isNotEmpty) return preview;
    final target = this.target;
    if (target == null) return missingValue;
    final name = target.displayName;
    return switch (type) {
      ReportTargetType.profile => '$name · ${target.university}',
      ReportTargetType.message => '$name 의 메시지',
      ReportTargetType.friendReview => '$name 의 리뷰',
      ReportTargetType.poll => '$name 의 투표 글',
    };
  }

  static ReportSummary fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'target_type': final String type,
      'target_id': final String targetId,
      'reason': final String reason,
      'status': final String status,
      'created_at': final String createdAt,
    }) {
      final kind = ReportTargetType.fromCode(type);
      final state = ReportStatus.fromCode(status);
      final at = DateTime.tryParse(createdAt);
      final note = json['reason_note'];
      final resolved = json['resolved_at'];
      if (kind != null && state != null && at != null && note is String? && resolved is String?) {
        return ReportSummary(
          id: id,
          type: kind,
          targetId: targetId,
          reason: reason,
          reasonNote: note,
          status: state,
          createdAt: at,
          resolvedAt: resolved == null ? null : DateTime.tryParse(resolved),
          target: ReportTarget.fromJson(json['target_profile']),
          openReporters: json['open_reporters'] is int ? json['open_reporters'] as int : null,
          preview: json['preview'] is String ? json['preview'] as String : null,
        );
      }
    }
    throw const FormatException('신고 한 줄의 모양이 아니에요');
  }
}

/// 신고 당시 사본. 종류마다 칸이 달라(메시지 body · 프로필 nickname/bio/avatar_url/photo_urls · 투표 question/option_* ·
/// 리뷰 tags/comment) 칸 이름으로 읽는다. 빠진 칸은 null — 화면이 "—" 로 그린다.
class ReportSnapshot {
  const ReportSnapshot(this.raw);

  final Map<String, Object?> raw;

  String? text(String key) {
    final value = raw[key];
    return value is String ? value : null;
  }

  /// 공개 아바타 URL(공개 버킷) — 없으면 null
  String? get avatarUrl => text('avatar_url');

  /// 실사진 5분 서명 URL 들(서명 못 한 파일은 서버가 뺐다)
  List<String> get photoUrls => _strings('photo_urls');

  List<String> get tags => _strings('tags');

  List<String> _strings(String key) {
    final value = raw[key];
    return value is List ? [for (final item in value) if (item is String) item] : const [];
  }
}

/// 같은 대상(같은 사람)의 다른 신고 한 줄
class OtherReport {
  const OtherReport({required this.id, required this.reason, required this.status, required this.createdAt});

  final String id;
  final String reason;
  final ReportStatus status;
  final DateTime createdAt;

  static OtherReport fromJson(Object? json) {
    if (json case {'id': final String id, 'reason': final String reason, 'status': final String status, 'created_at': final String createdAt}) {
      final state = ReportStatus.fromCode(status);
      final at = DateTime.tryParse(createdAt);
      if (state != null && at != null) return OtherReport(id: id, reason: reason, status: state, createdAt: at);
    }
    throw const FormatException('다른 신고 한 줄의 모양이 아니에요');
  }
}

/// 한 건(detail) — 요약 + 사본 + 글 상태 + 같은 대상의 신고자 수 · 다른 신고
class ReportDetail {
  const ReportDetail({
    required this.summary,
    required this.snapshot,
    required this.contentStatus,
    required this.openReporters,
    required this.otherReports,
  });

  final ReportSummary summary;
  final ReportSnapshot snapshot;

  /// 투표 글 · 리뷰 신고의 지금 글 상태. 글이 지워졌거나 글 신고가 아니면 null.
  final ContentStatus? contentStatus;

  /// 같은 대상의 열린 신고의 서로 다른 신고자 수(자동 가림 기준 3)
  final int openReporters;

  /// 최근 순 최대 20(서버)
  final List<OtherReport> otherReports;

  /// "같은 대상의 열린 신고 n건도 함께 닫기" 의 n.
  /// shortcut: 서버가 다른 신고를 20건까지만 싣는다 — 넘으면 실제로 닫히는 수보다 적게 보인다(계획서 편차 기록). 많아지면 서버에 수를 싣는다.
  int get openOthers => openOtherIds.length;

  /// 함께 닫기 · 가림 해제에 서버로 보내는 "운영자가 본 열린 신고" id — 대화상자의 n 과 같은 목록이다.
  List<String> get openOtherIds => [for (final o in otherReports) if (o.status == ReportStatus.open) o.id];

  static ReportDetail fromJson(Object? json) {
    if (json case {
      'snapshot': final Map<String, Object?> snapshot,
      'open_reporters': final int reporters,
      'other_reports': final List<Object?> others,
    }) {
      final content = json['content_status'];
      return ReportDetail(
        summary: ReportSummary.fromJson(json),
        snapshot: ReportSnapshot(snapshot),
        contentStatus: switch (content) {
          'visible' => ContentStatus.visible,
          'blinded' => ContentStatus.blinded,
          _ => null,
        },
        openReporters: reporters,
        otherReports: [for (final other in others) OtherReport.fromJson(other)],
      );
    }
    throw const FormatException('신고 한 건의 모양이 아니에요');
  }
}

/// 채팅 앞뒤 한 줄 — 글자만. 화면이 닫히면 버린다(저장 · 캐시 없음).
class ChatLine {
  const ChatLine({required this.id, required this.body, required this.fromTarget, required this.reported});

  final String id;
  final String body;

  /// 신고당한 사람이 보낸 줄(이름표 "신고 대상"), 아니면 "상대"
  final bool fromTarget;

  /// 신고된 그 줄
  final bool reported;

  static ChatLine fromJson(Object? json) {
    if (json case {'id': final String id, 'body': final String? body, 'from_target': final bool fromTarget, 'reported': final bool reported}) {
      return ChatLine(id: id, body: body ?? missingValue, fromTarget: fromTarget, reported: reported);
    }
    throw const FormatException('채팅 한 줄의 모양이 아니에요');
  }
}

/// "접수 뒤 지난 시간"(pen: 2일 5시간 · 22시간 · 1시간). 1시간 안은 "n분". 시계가 어긋나 미래면 0 으로 본다.
String formatElapsed(DateTime at, DateTime now) {
  final passed = now.difference(at);
  if (passed.inMinutes < 60) return '${passed.isNegative ? 0 : passed.inMinutes}분';
  if (passed.inHours < 24) return '${passed.inHours}시간';
  final hours = passed.inHours % 24;
  return hours == 0 ? '${passed.inDays}일' : '${passed.inDays}일 $hours시간';
}
