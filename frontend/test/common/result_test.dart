import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('성공 결과는 onSuccess 분기를 실행한다', () {
    const Result<int> result = Success<int>(3);

    final actual = result.when(
      onSuccess: (value) => value * 2,
      onFailure: (failure) => -1,
    );

    expect(actual, 6);
  });

  test('실패 결과는 onFailure 분기를 실행한다', () {
    const Result<int> result = FailureResult<int>(NetworkFailure());

    final actual = result.when(
      onSuccess: (value) => 'ok',
      onFailure: (failure) => failure.toDisplayMessage(),
    );

    expect(actual, '네트워크 연결을 확인해 주세요');
  });

  test('성공 결과는 실패 분기를 실행하지 않는다', () {
    const Result<String> result = Success<String>('value');
    var failureCallCount = 0;

    result.when(
      onSuccess: (value) => value,
      onFailure: (failure) {
        failureCallCount = failureCallCount + 1;
        return '';
      },
    );

    expect(failureCallCount, 0);
  });
}
