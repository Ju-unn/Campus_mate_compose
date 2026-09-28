import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/acquisition_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/acquisition_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_acquisition_repository.dart';

void main() {
  ProviderContainer container(FakeAcquisitionRepository repository) {
    final container = ProviderContainer(
      overrides: [acquisitionRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('아무것도 고르지 않으면 시작할 수 없다', () {
    expect(container(FakeAcquisitionRepository()).read(acquisitionViewModelProvider).canSubmit, isFalse);
  });

  test('기타가 아닌 칩 하나를 고르면 시작할 수 있다', () {
    final c = container(FakeAcquisitionRepository());
    c.read(acquisitionViewModelProvider.notifier).select(AcquisitionChannel.everytime);

    expect(c.read(acquisitionViewModelProvider).canSubmit, isTrue);
  });

  test('기타는 한 글자 이상 적어야 시작할 수 있다', () {
    final c = container(FakeAcquisitionRepository());
    final vm = c.read(acquisitionViewModelProvider.notifier)..select(AcquisitionChannel.other);
    expect(c.read(acquisitionViewModelProvider).canSubmit, isFalse);

    vm.changeNote('  ');
    expect(c.read(acquisitionViewModelProvider).canSubmit, isFalse);

    vm.changeNote('학교 축제');
    expect(c.read(acquisitionViewModelProvider).canSubmit, isTrue);
  });

  test('기타 글은 앞뒤 공백을 떼고 보낸다', () async {
    final repo = FakeAcquisitionRepository();
    final c = container(repo);
    final vm = c.read(acquisitionViewModelProvider.notifier)
      ..select(AcquisitionChannel.other)
      ..changeNote('  학교 축제  ');

    await vm.submit();

    expect(repo.submitted, (AcquisitionChannel.other, '학교 축제'));
    expect(c.read(acquisitionViewModelProvider).completed, isTrue);
  });

  test('기타가 아니면 적어 둔 글을 보내지 않는다', () async {
    final repo = FakeAcquisitionRepository();
    final vm = container(repo).read(acquisitionViewModelProvider.notifier)
      ..select(AcquisitionChannel.other)
      ..changeNote('학교 축제')
      ..select(AcquisitionChannel.instagram);

    await vm.submit();

    expect(repo.submitted, (AcquisitionChannel.instagram, null));
  });

  test('고르지 않고 누르면 보내지 않는다', () async {
    final repo = FakeAcquisitionRepository();

    await container(repo).read(acquisitionViewModelProvider.notifier).submit();

    expect(repo.submitted, isNull);
  });

  test('저장이 실패해도 문구를 보여 주고 머문다', () async {
    final repo = FakeAcquisitionRepository()..nextResult = const FailureResult(NetworkFailure());
    final c = container(repo);
    final vm = c.read(acquisitionViewModelProvider.notifier)..select(AcquisitionChannel.friend);

    await vm.submit();

    final state = c.read(acquisitionViewModelProvider);
    expect(state.errorMessage, '네트워크 연결을 확인해 주세요');
    expect(state.completed, isFalse);
    expect(state.isSubmitting, isFalse);
  });

  test('두 번 연달아 눌러도 한 번만 보낸다', () async {
    final repo = FakeAcquisitionRepository();
    final vm = container(repo).read(acquisitionViewModelProvider.notifier)..select(AcquisitionChannel.friend);

    await Future.wait([vm.submit(), vm.submit()]);

    expect(repo.submitCount, 1);
  });

  test('칩 다섯 개의 서버 값과 라벨이 계획서 표와 같다', () {
    expect(
      {for (final c in AcquisitionChannel.values) c.name: c.label},
      {
        'everytime': '에브리타임',
        'instagram': '인스타그램',
        'friend': '친구 소개',
        'community': '커뮤니티',
        'other': '기타',
      },
    );
  });
}
