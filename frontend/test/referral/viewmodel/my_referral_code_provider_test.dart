import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:campus_mate/referral/viewmodel/my_referral_code_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_referral_repository.dart';

void main() {
  late FakeReferralRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeReferralRepository();
    container = ProviderContainer(overrides: [referralRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);
    // autoDispose 라 듣는 쪽이 있어야 await 사이에 내려가지 않는다.
    final sub = container.listen(myReferralCodeProvider, (_, _) {});
    addTearDown(sub.close);
  });

  test('내 코드를 읽는다', () async {
    final result = await container.read(myReferralCodeProvider.future);
    expect(result.when(onSuccess: (code) => code, onFailure: (_) => null), 'K7QMX2');
  });

  test('실패도 던지지 않고 Result 로 준다', () async {
    repository.nextMyCode = const FailureResult(NetworkFailure());
    container.invalidate(myReferralCodeProvider);
    expect(await container.read(myReferralCodeProvider.future), isA<FailureResult<String>>());
  });

  test('invalidate 하면 다시 읽는다(다시 시도)', () async {
    await container.read(myReferralCodeProvider.future);
    container.invalidate(myReferralCodeProvider);
    await container.read(myReferralCodeProvider.future);
    expect(repository.myCodeCalls, 2);
  });
}
