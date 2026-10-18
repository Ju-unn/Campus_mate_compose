import 'package:campus_mate_admin/actions/action_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stats_fakes.dart';

/// D3 서버 계약(backend/app/admin/action_log.py)의 칸 이름 그대로 + 작업 이름 한국어(대장 결정 4)
void main() {
  ActionRow row(
    String action, {
    String? type,
    String? id,
    String? nickname,
    Map<String, Object?>? after,
    String? reason,
    String? email = 'admin@example.com',
  }) {
    return ActionRow.fromJson(
      actionRow('x', '2026-10-18T05:30:00+00:00', action, targetType: type, targetId: id, nickname: nickname, after: after, reason: reason, email: email),
    );
  }

  group('작업 이름', () {
    test('서버 action 값 → 한국어', () {
      expect(row('heart_task_approve').actionLabel, '인증샷 승인');
      expect(row('heart_task_reject').actionLabel, '인증샷 반려');
      expect(row('report_resolve', after: {'status': 'actioned'}).actionLabel, '신고 조치 완료');
      expect(row('report_resolve', after: {'status': 'dismissed'}).actionLabel, '신고 기각');
      expect(row('profile_suspend').actionLabel, '정지');
      expect(row('profile_unsuspend').actionLabel, '정지 해제');
      expect(row('profile_unhide').actionLabel, '가림 해제');
      expect(row('content_blind').actionLabel, '글 가림');
      expect(row('content_unblind').actionLabel, '글 가림 해제');
      expect(row('report_chat_view').actionLabel, '채팅 앞뒤 열람');
      expect(row('profile_note').actionLabel, '메모');
      expect(row('profile_private_view').actionLabel, '전화·카톡 열람');
      expect(row('account_close').actionLabel, '탈퇴 대행');
      expect(row('account_close_cleanup').actionLabel, '탈퇴 뒤 정리');
    });

    test('하트 조정은 부호 있는 수 — pen "하트 조정 +50"', () {
      expect(row('hearts_adjust', after: {'amount': 50}).actionLabel, '하트 조정 +50');
      expect(row('hearts_adjust', after: {'amount': -30}).actionLabel, '하트 조정 -30');
      expect(row('hearts_adjust').actionLabel, '하트 조정');
    });

    test('모르는 값은 그대로', () {
      expect(row('some_new_action').actionLabel, 'some_new_action');
    });
  });

  group('대상', () {
    test('사람은 닉네임(pen "닉네임B")', () {
      expect(row('profile_suspend', type: 'profile', id: 'b0000000-0000-4000-8000-000000000002', nickname: '닉네임B').targetLabel, '닉네임B');
    });

    test('닉네임이 없으면 종류 + 앞부분 + …(pen "제출 e41…")', () {
      expect(row('heart_task_approve', type: 'heart_task_submission', id: 'e4100000-0000-4000-8000-000000000001').targetLabel, '제출 e4100000…');
      expect(row('report_resolve', type: 'report', id: '12345678-0000-4000-8000-000000000001').targetLabel, '신고 12345678…');
      expect(row('profile_note', type: 'profile', id: 'abcdef12-0000-4000-8000-000000000001').targetLabel, '사용자 abcdef12…');
    });

    test('대상이 없으면 "-"', () {
      expect(row('x').targetLabel, '-');
    });
  });

  test('관리자 칸: 서버가 준 메일, 못 읽었으면(null) "admin"', () {
    expect(row('x').adminLabel, 'admin@example.com');
    expect(row('x', email: null).adminLabel, 'admin');
  });

  test('사유가 없으면 "-"', () {
    expect(row('x').reasonLabel, '-');
    expect(row('x', reason: '오류 보상').reasonLabel, '오류 보상');
  });

  group('대상 id 검색 모양 — UUID 만', () {
    test('하이픈 UUID(대 · 소문자)만 받는다', () {
      expect(isUuidShape('e4100000-0000-4000-8000-000000000001'), isTrue);
      expect(isUuidShape('E4100000-0000-4000-8000-00000000000A'), isTrue);
      expect(isUuidShape(' e4100000-0000-4000-8000-000000000001 '), isFalse); // 공백은 호출 쪽이 다듬는다
      expect(isUuidShape('닉네임A'), isFalse);
      expect(isUuidShape('e41'), isFalse);
      expect(isUuidShape('e4100000-0000-4000-8000-000000000001,or=(x)'), isFalse);
      expect(isUuidShape('e4100000000040008000000000000001'), isFalse);
    });
  });
}
