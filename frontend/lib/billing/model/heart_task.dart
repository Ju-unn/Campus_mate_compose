import 'package:campus_mate/billing/model/heart_task_pending.dart';

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
    this.canSubmit = false,
    this.maxPhotos = 0,
    this.pending = const [],
  });

  final HeartTaskKind kind;
  final int rewardHearts;
  final HeartTaskState state;

  /// 이번 달(투표는 이번 주) 쓴 횟수. 화면에는 보이지 않는다(대장 09-28) — 서버 판정 확인용으로만 둔다.
  final int used;
  final int limit;

  /// `state == rejected` 일 때만 있다.
  final HeartTaskRejectReason? rejectReason;

  /// 지금 낼 수 있나(인증 항목이고 한도가 남았다). 단톡방은 검수 중이어도 한도 안이면 true — [state] 가 reviewing 이어도 눌러서 이어 낸다.
  final bool canSubmit;

  /// 한 번에 낼 수 있는 사진 수(인증 항목 3, 투표 0). 옛 서버는 한 장까지라 1 로 읽는다.
  final int maxPhotos;

  /// 검수 중인 제출들(오래된 순). 18a 줄 아래 "검수 대기" 목록이 된다.
  final List<HeartTaskPending> pending;

  /// 모르는 항목 · 상태면 던진다 — `ApiClient.send` 가 받아서 알 수 없는 오류로 바꾼다.
  ///
  /// `can_submit` · `max_photos` · `pending` 은 2026-10-19 서버부터 온다. 없으면(옛 서버) 종전 규칙 —
  /// 인증 항목의 미완료 · 반려만 낼 수 있고, 사진은 한 장까지, 대기 목록은 없다.
  factory HeartTask.fromJson(Map<String, dynamic> json) {
    final kind = HeartTaskKind.tryParse(json['task'] as String) ?? (throw FormatException('heart task ${json['task']}'));
    final state = HeartTaskState.values.byName(json['state'] as String);
    final submittableByState = state == HeartTaskState.open || state == HeartTaskState.rejected;
    return HeartTask(
      kind: kind,
      rewardHearts: json['reward_hearts'] as int,
      state: state,
      used: json['used'] as int,
      limit: json['limit'] as int,
      rejectReason: HeartTaskRejectReason.tryParse(json['reject_reason'] as String?),
      canSubmit: json['can_submit'] as bool? ?? (kind.needsProof && submittableByState),
      maxPhotos: json['max_photos'] as int? ?? (kind.needsProof ? 1 : 0),
      pending: [
        for (final item in json['pending'] as List<dynamic>? ?? const []) HeartTaskPending.fromJson(item as Map<String, dynamic>),
      ],
    );
  }
}
