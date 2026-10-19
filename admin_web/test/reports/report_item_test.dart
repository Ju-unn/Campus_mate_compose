import 'package:campus_mate_admin/reports/report_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/report_fakes.dart';

/// 서버 모양(backend/app/admin/report_review.py `_summary` · `detail` · chat-context)을 읽는다.
void main() {
  group('목록 한 줄(_summary)', () {
    test('종류 · 사유 · 상태 · 시각 · 신고당한 사람을 읽는다', () {
      final item = ReportSummary.fromJson(
        reportRow('r1', type: 'profile', reason: 'spam', target: targetProfile(nickname: '닉네임E', university: '고려대학교')),
      );

      expect(item.id, 'r1');
      expect(item.type, ReportTargetType.profile);
      expect(item.status, ReportStatus.open);
      expect(reportReasonLabel(item.reason), '광고·스팸');
      expect(item.createdAt, DateTime.utc(2026, 10, 18, 2, 20));
      expect(item.target!.nickname, '닉네임E');
      expect(item.target!.isAutoHidden, isFalse);
    });

    test('대상 요약: 프로필 "닉네임 · 학교", 메시지 "닉네임 의 메시지", 리뷰 "닉네임 의 리뷰", 투표 "닉네임 의 투표 글"', () {
      String summary(String type) => ReportSummary.fromJson(reportRow('r', type: type)).targetSummary;

      expect(summary('profile'), '닉네임B · 연세대학교');
      expect(summary('message'), '닉네임B 의 메시지');
      expect(summary('friend_review'), '닉네임B 의 리뷰');
      expect(summary('poll'), '닉네임B 의 투표 글');
    });

    test('탈퇴로 대상이 지워졌으면(target_profile null) 대상 요약은 "—", 닉네임이 비면 "—"', () {
      expect(ReportSummary.fromJson(reportRow('r', target: null)).targetSummary, '—');
      expect(ReportSummary.fromJson(reportRow('r', type: 'profile', target: targetProfile(nickname: null))).targetSummary, '— · 연세대학교');
    });

    test('목록 줄의 신고자 수(open_reporters)를 읽는다 — 옛 응답처럼 칸이 없으면 null', () {
      expect(ReportSummary.fromJson(reportRow('r', openReporters: 3)).openReporters, 3);
      expect(ReportSummary.fromJson(reportRow('r', openReporters: 0)).openReporters, 0);
      expect(ReportSummary.fromJson({...reportRow('r')}..remove('open_reporters')).openReporters, isNull);
    });

    test('투표 글의 대상 요약은 질문 앞부분(preview)이 먼저, 없으면 "닉네임 의 투표 글"', () {
      String summary(String type, {String? preview}) =>
          ReportSummary.fromJson(reportRow('r', type: type, preview: preview)).targetSummary;

      expect(summary('poll', preview: '점심 뭐 먹을까요…'), '점심 뭐 먹을까요…');
      expect(summary('poll'), '닉네임B 의 투표 글');
      expect(summary('poll', preview: '  '), '닉네임B 의 투표 글');
      // 투표 글이 아닌 줄은 preview 가 와도 쓰지 않는다(서버는 보내지 않지만, 채팅 글자가 표에 오르지 않게)
      expect(summary('message', preview: '남의 글'), '닉네임B 의 메시지');
      expect(ReportSummary.fromJson({...reportRow('r', type: 'poll')}..remove('preview')).targetSummary, '닉네임B 의 투표 글');
    });

    test('사유 다섯 개는 앱 신고 시트와 같은 글자(pen yl8gX), 모르는 코드는 그대로', () {
      expect(
        ['abuse', 'sexual', 'spam', 'fake', 'other', 'new_code'].map(reportReasonLabel),
        ['욕설·비방·혐오', '성적 불쾌감', '광고·스팸', '사칭·허위', '기타', 'new_code'],
      );
    });

    test('모양이 틀리면 FormatException', () {
      expect(() => ReportSummary.fromJson({'id': 'r'}), throwsFormatException);
      expect(() => ReportSummary.fromJson(reportRow('r', type: 'unknown')), throwsFormatException);
    });
  });

  group('한 건(detail)', () {
    test('사본 · 글 상태 · 신고자 수 · 같은 대상의 다른 신고', () {
      final detail = ReportDetail.fromJson({
        ...reportRow('r1', type: 'poll'),
        'snapshot': defaultSnapshot('poll'),
        'content_status': 'blinded',
        'open_reporters': 2,
        'other_reports': [otherReport('o1'), otherReport('o2', status: 'dismissed')],
      });

      expect(detail.summary.id, 'r1');
      expect(detail.snapshot.text('question'), '학식 어때요?');
      expect(detail.contentStatus, ContentStatus.blinded);
      expect(detail.openReporters, 2);
      expect(detail.otherReports.map((o) => o.status), [ReportStatus.open, ReportStatus.dismissed]);
      expect(detail.openOthers, 1);
      // 함께 닫기 · 가림 해제에 보내는 "본 신고" 와 대화상자의 n 은 같은 목록에서 나온다
      expect(detail.openOtherIds, ['o1']);
    });

    test('프로필 사본: 공개 아바타 URL · 실사진 서명 URL 들, 없으면 null · 빈 목록', () {
      final withPhotos = ReportSnapshot(defaultSnapshot('profile'));
      final without = ReportSnapshot(const {'nickname': '여우비', 'bio': null, 'avatar_url': null, 'photo_urls': <Object?>[]});

      expect(withPhotos.avatarUrl, startsWith('https://storage.test/'));
      expect(withPhotos.photoUrls, hasLength(1));
      expect(without.avatarUrl, isNull);
      expect(without.photoUrls, isEmpty);
      expect(without.text('bio'), isNull);
    });

    test('지인 리뷰 사본의 태그 · 지워진 글(content_status null)', () {
      final detail = ReportDetail.fromJson({
        ...reportRow('r1', type: 'friend_review'),
        'snapshot': defaultSnapshot('friend_review'),
        'content_status': null,
        'open_reporters': 0,
        'other_reports': <Object?>[],
      });

      expect(detail.snapshot.tags, ['친절해요', '시간 잘 지켜요']);
      expect(detail.contentStatus, isNull);
    });
  });

  test('채팅 앞뒤 한 줄: 신고 대상이 보낸 줄 · 신고된 줄', () {
    final line = ChatLine.fromJson(chatLine('m6', '안녕', fromTarget: true, reported: true));

    expect((line.body, line.fromTarget, line.reported), ('안녕', true, true));
  });

  group('접수 뒤 지난 시간', () {
    final now = DateTime.utc(2026, 10, 18, 5, 20);

    test('1시간 안은 "n분", 하루 안은 "n시간", 그 뒤는 "n일 m시간"(0시간이면 "n일")', () {
      expect(formatElapsed(now.subtract(const Duration(minutes: 12)), now), '12분');
      expect(formatElapsed(now.subtract(const Duration(hours: 22, minutes: 59)), now), '22시간');
      expect(formatElapsed(now.subtract(const Duration(days: 2, hours: 5, minutes: 10)), now), '2일 5시간');
      expect(formatElapsed(now.subtract(const Duration(days: 3)), now), '3일');
    });

    test('시계가 어긋나 미래 시각이면 "0분"', () {
      expect(formatElapsed(now.add(const Duration(minutes: 5)), now), '0분');
    });
  });
}
