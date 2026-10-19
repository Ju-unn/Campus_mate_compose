import 'package:campus_mate_admin/matching/matching_item.dart';
import 'package:campus_mate_admin/widgets/status_badge.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stats_fakes.dart';

/// D4 서버 계약(backend/app/admin/matching.py)의 칸 이름 그대로. 사진 · 카톡 아이디 · 대화 칸은 모델에 없다.
void main() {
  group('MatchingSummary', () {
    test('칸 이름 그대로 읽고 share_rate(0~1)를 퍼센트 글자로', () {
      final s = MatchingSummary.fromJson(matchSummaryJson());
      expect((s.acceptsToday, s.acceptsYesterday, s.acceptsTotal, s.acceptersTotal, s.matchesTotal, s.sharedTotal), (18, 14, 436, 312, 67, 41));
      expect(s.shareRatePercent, '62%');
    });

    test('share_rate 가 null(매칭 0건)이면 "-"', () {
      expect(MatchingSummary.fromJson(matchSummaryJson(matches: 0, shared: 0, shareRate: null)).shareRatePercent, '-');
    });

    test('accepts_yesterday 가 없으면 null(보조 줄 생략 — 추측하지 않는다)', () {
      expect(MatchingSummary.fromJson(matchSummaryJson(yesterday: null)).acceptsYesterday, isNull);
    });

    test('정수 칸이 빠지면 형식 오류', () {
      expect(() => MatchingSummary.fromJson({'accepts_today': 1}), throwsFormatException);
    });
  });

  test('DailyMatching: date · accept_count · match_count · share_count', () {
    final d = DailyMatching.fromJson(matchDailyRow('2026-10-18', 27, 8, 5));
    expect((d.date, d.acceptCount, d.matchCount, d.shareCount), ('2026-10-18', 27, 8, 5));
  });

  group('MatchPair', () {
    test('id · matched_at · status · shared_at · a · b(id · nickname · university)', () {
      final p = MatchPair.fromJson(pairRow('m2', '2026-10-18T02:25:00+00:00', 'shared', sharedAt: '2026-10-18T03:40:00+00:00'));
      expect((p.id, p.status), ('m2', 'shared'));
      expect(p.sharedAt, DateTime.parse('2026-10-18T03:40:00+00:00'));
      expect((p.a.id, p.a.nickname, p.a.university), ('m2-a', '닉네임A', '서울대학교'));
    });

    test('탈퇴로 프로필이 없는 사람은 id · 닉네임이 null — 그래도 읽힌다', () {
      final p = MatchPair.fromJson(pairRow('m9', '2026-10-18T02:25:00+00:00', 'closed', b: {'id': null, 'nickname': null, 'university': null}));
      expect((p.b.id, p.b.nickname, p.b.withdrawn), (null, null, true));
      expect(p.a.withdrawn, false);
    });

    test('서버가 보내도 사진 · 카톡 아이디 · 대화 칸은 읽지 않는다(모델에 자리가 없다)', () {
      final row = pairRow('m1', '2026-10-18T05:02:00+00:00', 'chatting')..addAll({'kakao_id': 'secret', 'photo_path': 'p', 'last_message': 'hi'});
      expect(() => MatchPair.fromJson(row), returnsNormally);
    });
  });

  test('상태 배지: 대화 중 primary · 카톡 공유 완료 success · 닫힘 neutral · 모르는 값은 글자 그대로 neutral', () {
    expect(matchStatusBadge('chatting'), ('대화 중', StatusTone.primary));
    expect(matchStatusBadge('shared'), ('카톡 공유 완료', StatusTone.success));
    expect(matchStatusBadge('closed'), ('닫힘', StatusTone.neutral));
    expect(matchStatusBadge('x'), ('x', StatusTone.neutral));
  });

  test('"M/D HH:mm" — 한국 시각(UTC+9)', () {
    expect(formatMonthDayTime(DateTime.parse('2026-10-18T05:02:00+00:00')), '10/18 14:02');
    expect(formatMonthDayTime(DateTime.parse('2026-10-17T16:00:00+00:00')), '10/18 01:00');
  });
}
