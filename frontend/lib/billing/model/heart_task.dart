/// 18a 한 줄의 항목. [code] 는 서버 값 그대로다.
enum HeartTaskKind {
  everytimePost('everytime_post'),
  kakaoShare('kakao_share'),
  pollVote('poll_vote');

  const HeartTaskKind(this.code);

  final String code;

  /// 인증샷을 내는 항목인가. 투표 줄은 커뮤니티 탭에서 투표하면 저절로 쌓인다.
  bool get needsProof => this != pollVote;

  static HeartTaskKind? tryParse(String? code) {
    for (final kind in values) {
      if (kind.code == code) return kind;
    }
    return null;
  }
}

/// 18a 상태 넷(DESIGN §8.10). 판정은 서버가 한다(계획서 "API 계약").
enum HeartTaskState { open, reviewing, done, rejected }

/// 운영자가 고르는 반려 사유(계획서 D3). [label] 은 18b-2 "반려 사유: …" 뒤에 붙는다.
enum HeartTaskRejectReason {
  dateMissing('date_missing', '날짜가 안 보여요'),
  notVerified('not_verified', '게시글·공유가 확인되지 않아요'),
  reused('reused', '이미 쓴 캡처예요');

  const HeartTaskRejectReason(this.code, this.label);

  final String code;
  final String label;

  static HeartTaskRejectReason? tryParse(String? code) {
    for (final reason in values) {
      if (reason.code == code) return reason;
    }
    return null;
  }
}

/// `GET /heart-tasks` 의 한 줄.
class HeartTask {
  const HeartTask({
    required this.kind,
    required this.rewardHearts,
    required this.state,
    required this.used,
    required this.limit,
    this.rejectReason,
  });

  final HeartTaskKind kind;
  final int rewardHearts;
  final HeartTaskState state;

  /// 이번 달(투표는 이번 주) 쓴 횟수. 화면에는 보이지 않는다(대장 09-28) — 서버 판정 확인용으로만 둔다.
  final int used;
  final int limit;

  /// `state == rejected` 일 때만 있다.
  final HeartTaskRejectReason? rejectReason;

  /// 모르는 항목 · 상태면 던진다 — `ApiClient.send` 가 받아서 알 수 없는 오류로 바꾼다.
  factory HeartTask.fromJson(Map<String, dynamic> json) {
    return HeartTask(
      kind: HeartTaskKind.tryParse(json['task'] as String) ?? (throw FormatException('heart task ${json['task']}')),
      rewardHearts: json['reward_hearts'] as int,
      state: HeartTaskState.values.byName(json['state'] as String),
      used: json['used'] as int,
      limit: json['limit'] as int,
      rejectReason: HeartTaskRejectReason.tryParse(json['reject_reason'] as String?),
    );
  }
}
