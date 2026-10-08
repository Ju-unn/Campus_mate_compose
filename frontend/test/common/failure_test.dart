import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('네트워크 실패는 연결 확인 안내를 보여준다', () {
    const failure = NetworkFailure();

    expect(failure.toDisplayMessage(), '네트워크 연결을 확인해 주세요');
  });

  test('세션 만료 실패는 다시 로그인하라는 안내를 보여준다', () {
    const failure = SessionExpiredFailure();
    expect(failure.toDisplayMessage(), '세션이 만료됐어요, 다시 로그인해 주세요');
  });

  test('찾을 수 없음 실패는 대상이 없다는 안내를 보여준다', () {
    const failure = NotFoundFailure();

    expect(failure.toDisplayMessage(), '요청한 정보를 찾을 수 없습니다');
  });

  test('알 수 없는 실패는 일반 오류 안내를 보여준다', () {
    const failure = UnknownFailure();

    expect(failure.toDisplayMessage(), '알 수 없는 오류가 발생했습니다');
  });

  test('시간당 재전송 한도 실패는 잠시 후 다시 시도하라는 안내를 보여준다', () {
    const failure = RateLimitedFailure();
    expect(failure.toDisplayMessage(), '너무 많이 시도했어요. 잠시 후 다시 시도해 주세요');
  });

  test('가입 거부 실패는 서버가 준 이유를 그대로 보여준다', () {
    const failure = SignUpRejectedFailure('허용되지 않은 학교 이메일이에요');
    expect(failure.toDisplayMessage(), '허용되지 않은 학교 이메일이에요');
  });

  test('서버가 잠깐 못 받으면 잠시 뒤 다시 시도하라고 안내한다', () {
    const failure = ServerUnavailableFailure();
    expect(failure.toDisplayMessage(), '잠시 뒤 다시 시도해 주세요');
  });

  test('얼굴이 없으면 재촬영을 안내한다', () {
    const failure = NoFaceDetectedFailure();
    expect(failure.toDisplayMessage(), '얼굴이 보이는 사진으로 다시 올려주세요');
  });

  test('사진을 읽지 못하면 다른 사진을 고르라고 안내한다', () {
    const failure = PhotoUnreadableFailure();
    expect(failure.toDisplayMessage(), '사진을 읽을 수 없어요. 다른 사진으로 다시 올려주세요');
  });

  test('서버 거부 사유를 그대로 보여준다', () {
    const failure = ServerRejectedFailure('이미 검토 중이에요');
    expect(failure.toDisplayMessage(), '이미 검토 중이에요');
  });
  group('학교 메일 인증(02 · 03)', () {
    test('인증번호를 못 보냈으면 잠시 뒤 다시 하라는 임시 문구', () {
      expect(const CodeNotSentFailure().toDisplayMessage(), '인증번호를 보내지 못했어요. 잠시 뒤 다시 시도해 주세요');
    });

    test('학교 메일 인증을 못 마쳤으면 잠시 뒤 다시 하라는 임시 문구', () {
      expect(
        const SchoolEmailIncompleteFailure().toDisplayMessage(),
        '학교 메일 인증을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요',
      );
    });

    test('다른 소셜 계정이 쓰는 메일이면 그 수단의 한국어 이름으로 말하고, 그 계정으로 로그인하라고 덧붙인다', () {
      const cases = {'kakao': '카카오', 'google': '구글', 'apple': '애플'};
      for (final MapEntry(key: provider, value: label) in cases.entries) {
        final failure = SchoolEmailTakenFailure('서버 문구', provider);

        expect(failure.toDisplayMessage(), '이 메일은 $label로 가입돼 있어요', reason: provider);
        expect(failure.toHintMessage(), '$label 계정으로 로그인해 주세요', reason: provider);
      }
    });

    test('provider 가 email 이면 앱 상수 "이 학교 메일로 이미 가입된 계정이 있어요. 문의해 주세요", 보조 문구 없음', () {
      const failure = SchoolEmailTakenFailure('서버 문구', 'email');

      expect(failure.toDisplayMessage(), '이 학교 메일로 이미 가입된 계정이 있어요. 문의해 주세요');
      expect(failure.toHintMessage(), isNull);
    });

    test('모르는 수단이면 서버 문구를 그대로 쓰고 보조 문구는 없다', () {
      const failure = SchoolEmailTakenFailure('이 메일은 다른 수단으로 가입돼 있어요', 'line');

      expect(failure.toDisplayMessage(), '이 메일은 다른 수단으로 가입돼 있어요');
      expect(failure.toHintMessage(), isNull);
    });

    test('서버가 임시 토큰을 못 읽었으면(미확인) 다시 하라는 임시 문구', () {
      expect(
        const SchoolEmailNotConfirmedFailure().toDisplayMessage(),
        '학교 메일 인증을 마치지 못했어요. 잠시 뒤 다시 시도해 주세요',
      );
    });

    test('등록되지 않은 학교 · 재가입 제한(422)은 서버 문구를 그대로', () {
      expect(const SchoolEmailRejectedFailure('등록되지 않은 학교 메일이에요').toDisplayMessage(), '등록되지 않은 학교 메일이에요');
    });
  });
}
