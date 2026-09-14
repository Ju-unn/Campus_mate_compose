import 'package:campus_mate/common/failure.dart';

/// 성공과 실패를 하나의 타입으로 표현한다.
/// 값을 꺼내는 getter 를 두지 않고 [when] 으로만 다루게 해서
/// 실패 처리를 빠뜨리는 것을 막는다.
sealed class Result<T> {
  const Result();

  /// 성공과 실패 두 경우를 모두 처리해 하나의 값으로 접는다.
  R when<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  });
}

/// 작업이 성공해 값을 가진 결과.
final class Success<T> extends Result<T> {
  const Success(this._value);

  final T _value;

  @override
  R when<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  }) {
    return onSuccess(_value);
  }
}

/// 작업이 실패한 결과.
final class FailureResult<T> extends Result<T> {
  const FailureResult(this._failure);

  final Failure _failure;

  @override
  R when<R>({
    required R Function(T value) onSuccess,
    required R Function(Failure failure) onFailure,
  }) {
    return onFailure(_failure);
  }
}
