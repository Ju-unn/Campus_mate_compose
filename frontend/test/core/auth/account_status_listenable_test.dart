import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AccountStatusListenable listenable;
  late int notified;

  setUp(() {
    listenable = AccountStatusListenable();
    notified = 0;
    listenable.addListener(() => notified++);
  });

  tearDown(() => listenable.dispose());

  test('처음에는 active 다', () {
    expect(listenable.value, AccountStatus.active);
  });

  test('observe(SuspendedFailure) → suspended and notifies once', () {
    listenable.observe(const SuspendedFailure());

    expect(listenable.value, AccountStatus.suspended);
    expect(notified, 1);
  });

  test('observe(WithdrawnFailure) → withdrawn', () {
    listenable.observe(const WithdrawnFailure());

    expect(listenable.value, AccountStatus.withdrawn);
    expect(notified, 1);
  });

  test('observe(other failure) does nothing', () {
    for (final failure in <Failure>[
      const NetworkFailure(),
      const SessionExpiredFailure(),
      const ServerRejectedFailure('이용이 제한된 계정이에요'), // 문구가 같아도 헤더 없이는 정지가 아니다
      const UnknownFailure(),
    ]) {
      listenable.observe(failure);
    }

    expect(listenable.value, AccountStatus.active);
    expect(notified, 0);
  });

  test('same status twice notifies once', () {
    // 동시에 나간 요청 여럿이 한꺼번에 401 로 돌아와도 로그아웃은 한 번이어야 한다.
    listenable
      ..observe(const WithdrawnFailure())
      ..observe(const WithdrawnFailure())
      ..markWithdrawn();

    expect(listenable.value, AccountStatus.withdrawn);
    expect(notified, 1);
  });

  test('markWithdrawn → withdrawn', () {
    listenable.markWithdrawn();

    expect(listenable.value, AccountStatus.withdrawn);
    expect(notified, 1);
  });

  test('provider 는 한 컨테이너에서 같은 인스턴스를 준다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      identical(container.read(accountStatusListenableProvider), container.read(accountStatusListenableProvider)),
      isTrue,
    );
  });
}
