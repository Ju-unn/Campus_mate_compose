import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/community/model/data/poll_vote_notice.dart';
import 'package:campus_mate/community/view/poll_toast.dart';
import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = AppLocalizationsKo();

  group('pollVoteNoticeText', () {
    test('하트를 받았으면 보상 문구다', () {
      expect(pollVoteNoticeText(l10n, const PollVoteNotice.reward()), '하트 5개를 받았어요');
    });

    test('실패면 그 실패 종류의 글자다(앱이 정한 문구)', () {
      expect(pollVoteNoticeText(l10n, const PollVoteNotice.failed(NetworkFailure())), '네트워크 연결을 확인해 주세요');
    });

    test('서버가 거절한 실패는 서버 문구를 그대로 보인다', () {
      expect(pollVoteNoticeText(l10n, const PollVoteNotice.failed(ServerRejectedFailure('이미 투표했어요'))), '이미 투표했어요');
    });
  });
}
