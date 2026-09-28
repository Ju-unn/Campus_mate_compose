import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/referral/model/referral_repository_provider.dart';
import 'package:campus_mate/referral/viewmodel/referral_code_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_referral_repository.dart';

void main() {
  ProviderContainer container(FakeReferralRepository repository) {
    final container = ProviderContainer(
      overrides: [referralRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('6자가 되기 전에는 보낼 수 없다', () {
    final c = container(FakeReferralRepository());
    c.read(referralCodeViewModelProvider.notifier).changeCode('K7QMX');

    expect(c.read(referralCodeViewModelProvider).canSubmit, isFalse);
  });

  test('6자가 되면 보낼 수 있다', () {
    final c = container(FakeReferralRepository());
    c.read(referralCodeViewModelProvider.notifier).changeCode('K7QMX2');

    expect(c.read(referralCodeViewModelProvider).canSubmit, isTrue);
  });

  test('성공하면 referrerId 가 남는다(20d · 20b 로 갈 신호)', () async {
    final repo = FakeReferralRepository();
    final c = container(repo);
    final vm = c.read(referralCodeViewModelProvider.notifier)..changeCode('K7QMX2');

    await vm.submit();

    expect(repo.redeemedCodes, ['K7QMX2']);
    expect(c.read(referralCodeViewModelProvider).referrerId, '22222222-2222-2222-2222-222222222222');
  });

  test('409 · 404 · 422 는 서버 문구를 그대로 보여 주고 머문다', () async {
    final repo = FakeReferralRepository()
      ..nextRedeem = const FailureResult(ServerRejectedFailure('추천 코드는 한 번만 입력할 수 있어요'));
    final c = container(repo);
    final vm = c.read(referralCodeViewModelProvider.notifier)..changeCode('K7QMX2');

    await vm.submit();

    final state = c.read(referralCodeViewModelProvider);
    expect(state.errorMessage, '추천 코드는 한 번만 입력할 수 있어요');
    expect(state.referrerId, isNull);
    expect(state.isSubmitting, isFalse);
  });

  test('오류 뒤에 코드를 고치면 오류가 지워진다', () async {
    final repo = FakeReferralRepository()..nextRedeem = const FailureResult(ServerRejectedFailure('없는 코드예요'));
    final c = container(repo);
    final vm = c.read(referralCodeViewModelProvider.notifier)..changeCode('K7QMX2');
    await vm.submit();

    vm.changeCode('K7QMX');

    expect(c.read(referralCodeViewModelProvider).errorMessage, isNull);
  });

  test('두 번 연달아 눌러도 한 번만 보낸다', () async {
    final repo = FakeReferralRepository();
    final vm = container(repo).read(referralCodeViewModelProvider.notifier)..changeCode('K7QMX2');

    await Future.wait([vm.submit(), vm.submit()]);

    expect(repo.redeemedCodes, hasLength(1));
  });
}
