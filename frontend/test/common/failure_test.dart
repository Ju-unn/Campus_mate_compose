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

  test('얼굴이 없으면 재촬영을 안내한다', () {
    const failure = NoFaceDetectedFailure();
    expect(failure.toDisplayMessage(), '얼굴이 보이는 사진으로 다시 올려주세요');
  });

  test('서버 거부 사유를 그대로 보여준다', () {
    const failure = ServerRejectedFailure('이미 검토 중이에요');
    expect(failure.toDisplayMessage(), '이미 검토 중이에요');
  });
}
