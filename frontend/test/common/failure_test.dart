import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('네트워크 실패는 연결 확인 안내를 보여준다', () {
    const failure = NetworkFailure();

    expect(failure.toDisplayMessage(), '네트워크 연결을 확인해 주세요');
  });

  test('찾을 수 없음 실패는 대상이 없다는 안내를 보여준다', () {
    const failure = NotFoundFailure();

    expect(failure.toDisplayMessage(), '요청한 정보를 찾을 수 없습니다');
  });

  test('알 수 없는 실패는 일반 오류 안내를 보여준다', () {
    const failure = UnknownFailure();

    expect(failure.toDisplayMessage(), '알 수 없는 오류가 발생했습니다');
  });
}
