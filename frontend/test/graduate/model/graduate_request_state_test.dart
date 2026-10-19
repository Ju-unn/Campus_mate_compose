import 'package:campus_mate/graduate/model/graduate_request_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GraduateRejectReason', () {
    test('코드 네 개가 서버 계약과 같다', () {
      expect(
        GraduateRejectReason.values.map((reason) => reason.code),
        ['unreadable', 'not_certificate', 'unverifiable', 'school_unsupported'],
      );
    });

    test('tryParse 는 모르는 코드 · null 에 null', () {
      expect(GraduateRejectReason.tryParse('unverifiable'), GraduateRejectReason.unverifiable);
      expect(GraduateRejectReason.tryParse('whatever'), isNull);
      expect(GraduateRejectReason.tryParse(null), isNull);
    });
  });

  group('GraduateRequestState.tryParse', () {
    test('대기는 남은 횟수와 낸 시각을 읽는다', () {
      final state = GraduateRequestState.tryParse(
        {'state': 'pending', 'reject_reason': null, 'attempts_left': 2, 'submitted_at': '2026-10-19T01:00:00+00:00'},
      );

      expect(state, isA<GraduatePending>());
      final pending = state! as GraduatePending;
      expect(pending.attemptsLeft, 2);
      expect(pending.submittedAt, DateTime.utc(2026, 10, 19, 1));
    });

    test('낸 시각이 null 이거나 모양이 이상해도 대기는 대기다', () {
      for (final submittedAt in [null, 'not-a-date', 3]) {
        final state = GraduateRequestState.tryParse({'state': 'pending', 'attempts_left': 1, 'submitted_at': submittedAt});

        expect(state, isA<GraduatePending>(), reason: '$submittedAt');
        expect((state! as GraduatePending).submittedAt, isNull);
      }
    });

    test('반려는 사유와 남은 횟수를 읽는다', () {
      final state = GraduateRequestState.tryParse(
        {'state': 'rejected', 'reject_reason': 'not_certificate', 'attempts_left': 1},
      );

      final rejected = state! as GraduateRejected;
      expect(rejected.reason, GraduateRejectReason.notCertificate);
      expect(rejected.attemptsLeft, 1);
      expect(rejected.isExhausted(), isFalse);
    });

    test('반려 횟수가 0이면 소진이다', () {
      final state = GraduateRequestState.tryParse(
        {'state': 'rejected', 'reject_reason': 'unreadable', 'attempts_left': 0},
      );

      expect((state! as GraduateRejected).isExhausted(), isTrue);
    });

    test('모르는 사유 코드여도 반려는 반려다(사유만 비어 있다)', () {
      final state = GraduateRequestState.tryParse(
        {'state': 'rejected', 'reject_reason': 'new_reason', 'attempts_left': 2},
      );

      expect((state! as GraduateRejected).reason, isNull);
    });

    test('null · 모르는 상태 · 객체가 아닌 값은 null', () {
      expect(GraduateRequestState.tryParse(null), isNull);
      expect(GraduateRequestState.tryParse({'state': 'approved', 'attempts_left': 1}), isNull);
      expect(GraduateRequestState.tryParse('pending'), isNull);
      expect(GraduateRequestState.tryParse(<String, dynamic>{}), isNull);
    });

    test('attempts_left 가 없으면 0 으로 본다', () {
      final state = GraduateRequestState.tryParse({'state': 'pending'});

      expect((state! as GraduatePending).attemptsLeft, 0);
    });
  });
}
