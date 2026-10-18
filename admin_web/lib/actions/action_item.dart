/// 작업 기록(A7) 한 줄. 서버 모양은 D3 backend/app/admin/action_log.py 의 ActionRow.
/// IP · 바뀌기 전 값은 화면에 쓰지 않아 읽지 않는다.
library;

/// 대상 id 검색 칸이 받는 모양: 하이픈 UUID(서버 대상 id). 아니면 요청을 보내지 않는다.
bool isUuidShape(String text) => _uuid.hasMatch(text);

final RegExp _uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

class ActionRow {
  const ActionRow({
    required this.id,
    required this.createdAt,
    required this.adminEmail,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.targetNickname,
    required this.amount,
    required this.outcome,
    required this.reason,
  });

  final String id;
  final DateTime createdAt;
  final String? adminEmail;
  final String action;
  final String? targetType;
  final String? targetId;
  final String? targetNickname;

  /// 하트 조정의 부호 있는 수(`after.amount`)
  final int? amount;

  /// 신고 닫기 결과(`after.status` — `actioned` · `dismissed`)
  final String? outcome;
  final String? reason;

  /// "관리자" 칸 — 서버가 준 로그인 메일, 못 읽었으면 "admin"
  String get adminLabel => adminEmail ?? 'admin';

  /// "작업" 칸(대장 결정 4). 모르는 값은 서버 글자 그대로.
  String get actionLabel {
    return switch (action) {
      'heart_task_approve' => '인증샷 승인',
      'heart_task_reject' => '인증샷 반려',
      'report_resolve' => outcome == 'dismissed' ? '신고 기각' : '신고 조치 완료',
      'profile_suspend' => '정지',
      'profile_unsuspend' => '정지 해제',
      'profile_unhide' => '가림 해제',
      'content_blind' => '글 가림',
      'content_unblind' => '글 가림 해제',
      'report_chat_view' => '채팅 앞뒤 열람',
      'hearts_adjust' => amount == null ? '하트 조정' : '하트 조정 ${amount! > 0 ? '+' : ''}$amount',
      'profile_note' => '메모',
      'profile_private_view' => '전화·카톡 열람',
      'account_close' => '탈퇴 대행',
      'account_close_cleanup' => '탈퇴 뒤 정리',
      _ => action,
    };
  }

  /// "대상" 칸: 사람은 닉네임, 그 밖은 "제출 e4100000…"(종류 + 앞 8자)
  String get targetLabel {
    final nickname = targetNickname;
    if (nickname != null) return nickname;
    final type = targetType;
    final id = targetId;
    if (type == null || id == null) return '-';
    final kind = switch (type) {
      'heart_task_submission' => '제출',
      'report' => '신고',
      'profile' => '사용자',
      'poll' => '투표',
      'friend_review' => '리뷰',
      _ => type,
    };
    return '$kind ${id.length > 8 ? id.substring(0, 8) : id}…';
  }

  String get reasonLabel => reason ?? '-';

  static ActionRow fromJson(Object? json) {
    if (json case {'id': final String id, 'created_at': final String at, 'action': final String action}) {
      final created = DateTime.tryParse(at);
      final after = json['after'];
      final amount = after is Map ? after['amount'] : null;
      final outcome = after is Map ? after['status'] : null;
      if (created != null &&
          json['admin_email'] is String? &&
          json['target_type'] is String? &&
          json['target_id'] is String? &&
          json['target_nickname'] is String? &&
          json['reason'] is String? &&
          amount is int? &&
          outcome is String?) {
        return ActionRow(
          id: id,
          createdAt: created,
          adminEmail: json['admin_email'] as String?,
          action: action,
          targetType: json['target_type'] as String?,
          targetId: json['target_id'] as String?,
          targetNickname: json['target_nickname'] as String?,
          amount: amount,
          outcome: outcome,
          reason: json['reason'] as String?,
        );
      }
    }
    throw const FormatException('작업 기록 한 줄의 모양이 아니에요');
  }
}
