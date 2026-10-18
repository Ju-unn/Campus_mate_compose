import 'package:campus_mate_admin/home/home_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stats_fakes.dart';

/// D4 서버 계약(backend/app/admin/stats.py · health.py)의 칸 이름 그대로 읽는다 — 추측하지 않는다.
void main() {
  group('HomeStats', () {
    test('open_reports · pending_proofs · signups_today 를 읽는다', () {
      final stats = HomeStats.fromJson({
        'profiles': {'pending': 3, 'active': 311, 'suspended': 2, 'withdrawn': 9},
        'open_reports': 5,
        'pending_proofs': 12,
        'signups_today': 38,
        'signups_7d': 210,
      });
      expect((stats.pendingProofs, stats.openReports, stats.signupsToday), (12, 5, 38));
    });

    test('칸이 빠지면 형식 오류', () {
      expect(() => HomeStats.fromJson({'open_reports': 5}), throwsFormatException);
    });
  });

  test('DailyStat: date · male_signups · female_signups · report_count · proof_count', () {
    final day = DailyStat.fromJson({'date': '2026-10-14', 'male_signups': 4, 'female_signups': 3, 'report_count': 8, 'proof_count': 15});
    expect((day.date, day.maleSignups, day.femaleSignups, day.reportCount, day.proofCount), ('2026-10-14', 4, 3, 8, 15));
    expect(() => DailyStat.fromJson({'date': '2026-10-14'}), throwsFormatException);
  });

  group('UniversityStatus', () {
    test('이름 · 활성 인원 · 카드 오픈 시각(없으면 null)', () {
      final u = UniversityStatus.fromJson(universityRow('서울대학교', 62, 58));
      expect((u.name, u.maleActive, u.femaleActive), ('서울대학교', 62, 58));
      expect(u.cardOpensAt, DateTime.parse('2026-11-01T22:00:00+00:00'));
      expect(UniversityStatus.fromJson(universityRow('고려대학교', 1, 2, opensAt: null)).cardOpensAt, isNull);
    });

    test('가로 막대 이름: "…대학교" → "…대"(pen 서울대), 그 밖은 그대로', () {
      expect(shortSchoolName('서울대학교'), '서울대');
      expect(shortSchoolName('이화여자대학교'), '이화여자대');
      expect(shortSchoolName('한국과학기술원'), '한국과학기술원');
    });
  });

  group('HealthReport', () {
    test('items(key · status · count) 와 unobservable 을 읽는다', () {
      final health = HealthReport.fromJson(healthJson());
      expect(health.items.length, 5);
      expect((health.items[1].key, health.items[1].status, health.items[1].count), ('stuck_chat_rooms', 'warn', 2));
      expect(health.unobservable, ['refund_batch']);
    });

    test('줄 문구 · 단위: 키마다(문구는 pen, 단위는 pen "2개" · "4건" 에서 이어 정함)', () {
      expect(healthLabel('cards_issued_today'), '오늘 카드가 도착했는지 (지급 요일 기준)');
      expect(healthLabel('stuck_chat_rooms'), '48시간 지나도 안 닫힌 방');
      expect(healthLabel('overdue_withdrawn'), '탈퇴 31일 넘은 미삭제 프로필');
      expect(healthLabel('avatar_failures_24h'), '최근 24시간 아바타 생성 실패');
      expect(healthLabel('stuck_pending_pushes'), '오래 쌓인 푸시');
      expect(healthLabel('모르는'), isNull);
      expect(healthCountLabel('stuck_chat_rooms', 2), '2개');
      expect(healthCountLabel('avatar_failures_24h', 4), '4건');
      // D4 검토 반영(10-18): 카드 줄 count = 점검 대상 지역 수(한 곳도 못 받았을 때만 위험) → "n곳"
      expect(healthCountLabel('cards_issued_today', 2), '2곳');
    });
  });
}
