import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/tag_picker_repository.dart';
import 'package:campus_mate/profile/model/tag_picker_repository_provider.dart';
import 'package:campus_mate/profile/model/tags.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_onboarding_repository.dart';

class _FakeTagPickerRepository implements TagPickerRepository {
  List<String>? submittedTags;
  Result<void> nextResult = const Success(null);

  @override
  Future<Result<void>> submit(String endpoint, List<String> tags) async {
    submittedTags = tags;
    return nextResult;
  }
}

void main() {
  late _FakeTagPickerRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;

  setUp(() {
    repository = _FakeTagPickerRepository();
    onboardingRepository = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        tagPickerRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('3개 미만 고르면 다음 버튼이 비활성', () {
    final vm = container.read(tagPickerViewModelProvider(TagPickerKind.interests).notifier);
    vm.toggle(interestTags[0]);
    vm.toggle(interestTags[1]);
    final state = container.read(tagPickerViewModelProvider(TagPickerKind.interests));
    expect(state.canSubmit, isFalse);
  });

  test('5개 넘게 고르려 하면 무시한다', () {
    final vm = container.read(tagPickerViewModelProvider(TagPickerKind.interests).notifier);
    for (final tag in interestTags.take(6)) {
      vm.toggle(tag);
    }
    final state = container.read(tagPickerViewModelProvider(TagPickerKind.interests));
    expect(state.selected.length, 5);
  });

  test('다시 누르면 선택이 풀린다', () {
    final vm = container.read(tagPickerViewModelProvider(TagPickerKind.interests).notifier);
    vm.toggle(interestTags[0]);
    vm.toggle(interestTags[0]);
    final state = container.read(tagPickerViewModelProvider(TagPickerKind.interests));
    expect(state.selected, isEmpty);
  });

  test('3~5개면 제출 가능하고 성공하면 completed 가 켜진다', () async {
    final vm = container.read(tagPickerViewModelProvider(TagPickerKind.interests).notifier);
    vm.toggle(interestTags[0]);
    vm.toggle(interestTags[1]);
    vm.toggle(interestTags[2]);
    await vm.submit();
    final state = container.read(tagPickerViewModelProvider(TagPickerKind.interests));
    expect(state.completed, isTrue);
    expect(repository.submittedTags, hasLength(3));
  });

  test('kind 마다 다른 풀을 쓴다', () {
    expect(TagPickerKind.interests.pool, interestTags);
    expect(TagPickerKind.myTraits.pool, myTraits);
    expect(TagPickerKind.idealTraits.pool, idealTraits);
  });

  test('최소·최대 개수는 한 곳에서 오고 라벨도 그 숫자를 쓴다', () {
    expect((TagPickerKind.minCount, TagPickerKind.maxCount), (3, 5));
    for (final kind in TagPickerKind.values) {
      expect(kind.tagLabel, endsWith('(최소 3개 · 최대 5개)'));
    }
  });
}
