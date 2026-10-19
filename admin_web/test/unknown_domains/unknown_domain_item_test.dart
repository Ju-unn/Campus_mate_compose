import 'package:campus_mate_admin/unknown_domains/unknown_domain_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stats_fakes.dart';

void main() {
  test('UnknownDomain: domain · attempt_count · last_seen_at (first_seen_at 은 읽지 않는다)', () {
    final d = UnknownDomain.fromJson(domainRow('example-univ.ac.kr', 12, '2026-10-18T04:40:00+00:00'));
    expect((d.domain, d.attemptCount, d.lastSeenAt), ('example-univ.ac.kr', 12, DateTime.parse('2026-10-18T04:40:00+00:00')));
  });

  test('칸이 빠지면 형식 오류', () {
    expect(() => UnknownDomain.fromJson({'domain': 'a'}), throwsFormatException);
  });
}
