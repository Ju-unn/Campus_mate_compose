import 'package:campus_mate/auth/model/verification_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버 `GET /me/verification-status` 응답을 흉내 낸다. `null` 로 둔 칸은 응답에 아예 없다(옛 서버).
Map<String, dynamic> _status({
  String? consent = 'current',
  bool? schoolEmailVerified = false,
  bool hasSchoolInfo = false,
  Object? graduateEnabled,
  Object? method,
  Object? graduate,
}) {
  return {
    'status': 'verified',
    'has_school_info': hasSchoolInfo,
    'consent': ?consent,
    'school_email_verified': ?schoolEmailVerified,
    'graduate_enabled': ?graduateEnabled,
    'verification_method': ?method,
    'graduate': ?graduate,
  };
}

Map<String, dynamic> _graduate(String state, {int attemptsLeft = 2, String? reason}) => {
      'state': state,
      'reject_reason': reason,
      'attempts_left': attemptsLeft,
      'submitted_at': '2026-10-19T01:00:00+00:00',
    };

void main() {
  group('졸업생 칸이 꺼져 있거나 없으면 지금 동작 그대로', () {
    test('옛 서버 응답(새 칸 없음) + 미인증 → needsSchoolEmail', () {
      expect(VerificationGate.fromStatus(_status()), VerificationGate.needsSchoolEmail);
    });

    test('graduate_enabled=false 면 방법·신청 칸이 무엇이든 needsSchoolEmail', () {
      final rows = <Map<String, dynamic>>[
        _status(graduateEnabled: false),
        _status(graduateEnabled: false, method: 'graduate_certificate'),
        _status(graduateEnabled: false, method: 'graduate_certificate', graduate: _graduate('pending')),
        _status(graduateEnabled: false, graduate: _graduate('rejected', reason: 'unreadable')),
      ];
      for (final row in rows) {
        expect(VerificationGate.fromStatus(row), VerificationGate.needsSchoolEmail, reason: '$row');
      }
    });

    test('graduate_enabled 가 true 가 아닌 값(문자열 등)이면 꺼진 것으로 본다', () {
      expect(VerificationGate.fromStatus(_status(graduateEnabled: 'true')), VerificationGate.needsSchoolEmail);
    });
  });

  group('graduate_enabled=true 판정표', () {
    final rows = <(String, Map<String, dynamic>, VerificationGate)>[
      ('방법 null', _status(graduateEnabled: true, method: null), VerificationGate.needsVerificationMethod),
      ('방법 칸 없음', _status(graduateEnabled: true), VerificationGate.needsVerificationMethod),
      ('모르는 방법 문자열', _status(graduateEnabled: true, method: 'phone'), VerificationGate.needsVerificationMethod),
      ('학교 메일', _status(graduateEnabled: true, method: 'school_email'), VerificationGate.needsSchoolEmailChosen),
      (
        '졸업증명서',
        _status(graduateEnabled: true, method: 'graduate_certificate'),
        VerificationGate.needsGraduateApplication,
      ),
      (
        '졸업증명서 + 대기',
        _status(graduateEnabled: true, method: 'graduate_certificate', graduate: _graduate('pending')),
        VerificationGate.graduateReviewing,
      ),
      (
        '졸업증명서 + 반려(횟수 남음)',
        _status(
          graduateEnabled: true,
          method: 'graduate_certificate',
          graduate: _graduate('rejected', reason: 'unreadable'),
        ),
        VerificationGate.needsGraduateApplication,
      ),
      (
        '졸업증명서 + 반려(횟수 0)',
        _status(
          graduateEnabled: true,
          method: 'graduate_certificate',
          graduate: _graduate('rejected', attemptsLeft: 0, reason: 'unverifiable'),
        ),
        VerificationGate.needsGraduateApplication,
      ),
      // 서버는 방법이 졸업증명서일 때만 graduate 를 채우지만, 칸이 오면 그 상태가 방법보다 앞선다.
      (
        '방법 null 인데 반려가 오면 신청 폼',
        _status(graduateEnabled: true, graduate: _graduate('rejected', reason: 'not_certificate')),
        VerificationGate.needsGraduateApplication,
      ),
      (
        '모르는 graduate 상태는 방법으로 판단',
        _status(graduateEnabled: true, method: 'graduate_certificate', graduate: _graduate('approved')),
        VerificationGate.needsGraduateApplication,
      ),
    ];
    for (final (name, status, expected) in rows) {
      test('$name → $expected', () {
        expect(VerificationGate.fromStatus(status), expected);
      });
    }
  });

  group('인증을 마친 사람은 졸업생 칸을 보지 않는다', () {
    test('학교 메일 인증 + 아무 졸업생 칸 → 예전과 같은 needsSchoolInfo / complete', () {
      for (final graduate in [null, _graduate('pending'), _graduate('rejected', reason: 'unreadable')]) {
        expect(
          VerificationGate.fromStatus(_status(
            schoolEmailVerified: true,
            graduateEnabled: true,
            method: 'graduate_certificate',
            graduate: graduate,
          )),
          VerificationGate.needsSchoolInfo,
        );
        expect(
          VerificationGate.fromStatus(_status(
            schoolEmailVerified: true,
            hasSchoolInfo: true,
            graduateEnabled: true,
            method: 'graduate_certificate',
            graduate: graduate,
          )),
          VerificationGate.complete,
        );
      }
    });

    test('졸업생 승인 뒤(서버가 school_email_verified=true 로 내림) 학과 정보가 없으면 3c 로 간다', () {
      expect(
        VerificationGate.fromStatus(
          _status(schoolEmailVerified: true, graduateEnabled: true, method: 'graduate_certificate'),
        ),
        VerificationGate.needsSchoolInfo,
      );
    });
  });

  group('동의가 가장 먼저다', () {
    test('동의 전이면 졸업생 칸이 켜져 있어도 needsConsent', () {
      expect(
        VerificationGate.fromStatus(_status(consent: 'none', graduateEnabled: true)),
        VerificationGate.needsConsent,
      );
    });

    test('재동의면 needsConsentRenewal', () {
      expect(
        VerificationGate.fromStatus(_status(consent: 'outdated', graduateEnabled: true, method: 'school_email')),
        VerificationGate.needsConsentRenewal,
      );
    });
  });
}
