import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/tag_picker_repository.dart';
import 'package:campus_mate/profile/model/tag_picker_repository_provider.dart';
import 'package:campus_mate/profile/model/tags.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';

import '../model/fake_onboarding_repository.dart';
import '../../core/draft/fake_draft_store.dart';

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

  group('임시 저장', () {
    late FakeDraftStore drafts;

    setUp(() => drafts = FakeDraftStore());

    /// 앱을 다시 연 것처럼 새 컨테이너(새 뷰모델)를 만든다. 저장소는 같은 것을 쓴다.
    ProviderContainer open() {
      final opened = ProviderContainer(
        overrides: [
          tagPickerRepositoryProvider.overrideWithValue(repository),
          onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
          draftStoreProvider.overrideWithValue(drafts),
        ],
      );
      addTearDown(opened.dispose);
      return opened;
    }

    test('세 화면(관심사 · 나의 특징 · 이상형 특징)이 각자 저장되고 새로 만들면 돌아온다', () {
      final opened = open();
      opened.read(tagPickerViewModelProvider(TagPickerKind.interests).notifier).toggle(interestTags[0]);
      opened.read(tagPickerViewModelProvider(TagPickerKind.myTraits).notifier).toggle(myTraits[1]);
      opened.read(tagPickerViewModelProvider(TagPickerKind.idealTraits).notifier).toggle(idealTraits[2]);

      final reopened = open();
      expect(reopened.read(tagPickerViewModelProvider(TagPickerKind.interests)).selected, {interestTags[0]});
      expect(reopened.read(tagPickerViewModelProvider(TagPickerKind.myTraits)).selected, {myTraits[1]});
      expect(reopened.read(tagPickerViewModelProvider(TagPickerKind.idealTraits)).selected, {idealTraits[2]});
    });

    test('"다음" 이 성공하면 그 화면 값만 지운다', () async {
      final opened = open();
      final interests = opened.read(tagPickerViewModelProvider(TagPickerKind.interests).notifier);
      interestTags.take(3).forEach(interests.toggle);
      opened.read(tagPickerViewModelProvider(TagPickerKind.myTraits).notifier).toggle(myTraits[0]);

      await interests.submit();

      expect(drafts.cleared, [DraftScreen.interests]);
      final reopened = open();
      expect(reopened.read(tagPickerViewModelProvider(TagPickerKind.interests)).selected, isEmpty);
      expect(reopened.read(tagPickerViewModelProvider(TagPickerKind.myTraits)).selected, {myTraits[0]});
    });

    test('목록에 없는 태그(앱 업데이트로 빠진 태그)는 빼고 돌려준다', () {
      drafts.saved['account-a/${DraftScreen.interests.key}'] =
          '{"selected": ["${interestTags[0]}", "사라진 태그"]}';

      expect(open().read(tagPickerViewModelProvider(TagPickerKind.interests)).selected, {interestTags[0]});
    });
  });
}
