import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/me/viewmodel/tag_edit_view_model.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/model/tag_picker_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_kind.dart';
import 'package:campus_mate/profile/viewmodel/tag_picker_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_mate/core/draft/draft_store.dart';

import '../../profile/model/fake_onboarding_repository.dart';
import '../../profile/model/fake_tag_picker_repository.dart';
import '../model/fake_me_repository.dart';
import '../../core/draft/fake_draft_store.dart';

const _profile = MyProfile(
  nickname: '여우',
  age: 23,
  university: '가나대학교',
  major: null,
  heightCm: null,
  mbti: null,
  avatarUrl: null,
  preferredAgeMin: 22,
  preferredAgeMax: 27,
  preferredHeightMin: null,
  preferredHeightMax: null,
  bio: '안녕하세요',
  interestTags: ['카페가기', '여행', '요리'],
  myTraits: ['유머러스', '성실한', '차분한', '다정한'],
  idealTraits: ['솔직한', '연락 잘하는', '다정한'],
);

void main() {
  late FakeMeRepository me;
  late FakeTagPickerRepository tags;
  late FakeOnboardingRepository onboarding;
  late ProviderContainer container;
  late FakeDraftStore drafts;

  setUp(() async {
    drafts = FakeDraftStore();
    me = FakeMeRepository(const Success(_profile));
    tags = FakeTagPickerRepository();
    onboarding = FakeOnboardingRepository();
    container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(me),
        tagPickerRepositoryProvider.overrideWithValue(tags),
        onboardingRepositoryProvider.overrideWithValue(onboarding),
        draftStoreProvider.overrideWithValue(drafts),
      ],
    );
    // 편집 화면은 화면 15 · 15c 를 거쳐 열린다 — 그때는 내 프로필이 이미 읽혀 있다.
    await container.read(myProfileProvider.future);
  });

  tearDown(() => container.dispose());

  for (final (kind, expected) in [
    (TagPickerKind.interests, _profile.interestTags),
    (TagPickerKind.myTraits, _profile.myTraits),
    (TagPickerKind.idealTraits, _profile.idealTraits),
  ]) {
    test('열면 서버의 ${kind.name} 태그가 골라진 채다', () {
      expect(container.read(tagEditViewModelProvider(kind)).selected, expected.toSet());
    });
  }

  test('저장하면 온보딩과 같은 endpoint 로 보내고 화면 15 값을 다시 읽는다 — 온보딩 단계는 조회하지 않는다', () async {
    final subscription = container.listen(tagEditViewModelProvider(TagPickerKind.interests), (_, _) {});
    addTearDown(subscription.close);
    final viewModel = container.read(tagEditViewModelProvider(TagPickerKind.interests).notifier);
    viewModel.toggle('카페가기');
    viewModel.toggle('독서');

    await viewModel.submit();
    await container.read(myProfileProvider.future);

    expect(tags.submittedEndpoint, 'interests');
    expect(tags.submittedTags!.toSet(), {'여행', '요리', '독서'});
    expect(subscription.read().completed, isTrue);
    expect(me.calls, 2, reason: '저장 뒤 invalidate 로 GET /me/profile 을 한 번 더 부른다');
    expect(onboarding.fetchCount, 0);
  });

  test('온보딩 모드는 그대로 — 저장 뒤 온보딩 단계를 다시 조회하고 화면 15 값은 건드리지 않는다', () async {
    final viewModel = container.read(tagPickerViewModelProvider(TagPickerKind.interests).notifier);
    for (final tag in ['카페가기', '여행', '요리']) {
      viewModel.toggle(tag);
    }

    await viewModel.submit();
    await Future<void>.delayed(Duration.zero);

    expect(onboarding.fetchCount, 1);
    expect(me.calls, 1);
  });

  test('저장이 실패하면 문구를 보이고 끝나지 않는다 — 화면 15 값도 다시 읽지 않는다', () async {
    tags.nextResult = const FailureResult(NetworkFailure());
    final subscription = container.listen(tagEditViewModelProvider(TagPickerKind.myTraits), (_, _) {});
    addTearDown(subscription.close);

    await container.read(tagEditViewModelProvider(TagPickerKind.myTraits).notifier).submit();

    expect(subscription.read().completed, isFalse);
    expect(subscription.read().errorMessage, const NetworkFailure().toDisplayMessage());
    expect(me.calls, 1);
  });

  test('저장 중에 화면을 떠나도(autoDispose) 끝난 저장이 오류를 내지 않고 화면 15 는 다시 읽힌다', () async {
    tags.hold = Completer<void>();
    final provider = tagEditViewModelProvider(TagPickerKind.interests);
    final subscription = container.listen(provider, (_, _) {});
    final saving = container.read(provider.notifier).submit();

    subscription.close();
    await Future<void>.delayed(Duration.zero);
    tags.hold!.complete();
    await saving;
    await container.read(myProfileProvider.future);

    expect(tags.submittedEndpoint, 'interests');
    expect(me.calls, 2);
  });

  test('tag_edit_is_filled_from_the_server_each_time_it_opens — 고르다 만 값은 닫으면 사라진다(Review Focus 5)', () async {
    final provider = tagEditViewModelProvider(TagPickerKind.interests);
    final first = container.listen(provider, (_, _) {});
    container.read(provider.notifier).toggle('카페가기');
    expect(first.read().selected, {'여행', '요리'});

    // 화면을 닫으면 듣는 쪽이 없어져 autoDispose 가 버린다.
    first.close();
    await Future<void>.delayed(Duration.zero);
    final second = container.listen(provider, (_, _) {});
    addTearDown(second.close);

    expect(second.read().selected, {'카페가기', '여행', '요리'});
  });

  test('편집 모드는 임시 저장을 하지 않는다 — 온보딩 값을 쓰지도 지우지도 않는다', () async {
    // 편집은 열 때마다 서버 값으로 채운다. 고르다 만 값이 온보딩 임시 저장 자리에 섞이면 안 된다.
    final subscription = container.listen(tagEditViewModelProvider(TagPickerKind.interests), (_, _) {});
    addTearDown(subscription.close);
    final viewModel = container.read(tagEditViewModelProvider(TagPickerKind.interests).notifier);
    viewModel.toggle('독서');

    await viewModel.submit();

    expect(subscription.read().completed, isTrue);
    expect(drafts.saved, isEmpty);
    expect(drafts.cleared, isEmpty);
  });
}
