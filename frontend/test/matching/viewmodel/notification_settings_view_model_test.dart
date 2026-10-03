import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_repository_provider.dart';
import 'package:campus_mate/matching/model/notification_preferences.dart';
import 'package:campus_mate/matching/viewmodel/notification_settings_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_card_repository.dart';

void main() {
  late FakeCardRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = FakeCardRepository();
    container = ProviderContainer(
      overrides: [cardRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() => container.dispose());

  test('행이 없는 사람은 전부 켜짐, 마케팅만 꺼짐으로 그린다', () async {
    repository.preferences = const Success(NotificationPreferences());

    await container.read(notificationSettingsViewModelProvider.notifier).refresh();

    final state = container.read(notificationSettingsViewModelProvider);
    expect(state.preferences.cardArrived, isTrue);
    expect(state.preferences.marketing, isFalse);
  });

  test('스위치를 끄면 그 값만 서버로 간다', () async {
    await container.read(notificationSettingsViewModelProvider.notifier).refresh();

    await container.read(notificationSettingsViewModelProvider.notifier)
        .toggle('card_arrived', false);

    expect(repository.preferenceUpdates.single, (key: 'card_arrived', value: false));
  });

  test('저장에 실패하면 스위치를 원래대로 되돌린다', () async {
    await container.read(notificationSettingsViewModelProvider.notifier).refresh();
    repository.writeResult = const FailureResult(NetworkFailure());

    await container.read(notificationSettingsViewModelProvider.notifier)
        .toggle('match_made', false);

    final state = container.read(notificationSettingsViewModelProvider);
    expect(state.preferences.matchMade, isTrue);
    expect(state.errorMessage, const NetworkFailure().toDisplayMessage());
  });

  test('매칭 일시중지는 프로필 쪽으로 간다', () async {
    await container.read(notificationSettingsViewModelProvider.notifier).setPaused(true);

    expect(repository.pausedValue, isTrue);
  });

  test('일시중지해 둔 사람은 다시 열어도 서버 값대로 꺼짐이다(A14)', () async {
    repository.paused = const Success(true);

    await container.read(notificationSettingsViewModelProvider.notifier).refresh();

    expect(container.read(notificationSettingsViewModelProvider).matchingPaused, isTrue);
  });

  test('일시중지 값을 못 읽으면 안내를 띄운다 — 켜짐으로 아는 척하지 않는다', () async {
    repository.paused = const FailureResult(NetworkFailure());

    await container.read(notificationSettingsViewModelProvider.notifier).refresh();

    final state = container.read(notificationSettingsViewModelProvider);
    expect(state.isLoading, isFalse);
    expect(state.errorMessage, const NetworkFailure().toDisplayMessage());
  });

  test('알림 설정만 못 읽어도 안내는 남고 일시중지는 서버 값대로다', () async {
    repository.preferences = const FailureResult(NetworkFailure());
    repository.paused = const Success(true);

    await container.read(notificationSettingsViewModelProvider.notifier).refresh();

    final state = container.read(notificationSettingsViewModelProvider);
    expect(state.matchingPaused, isTrue);
    expect(state.errorMessage, const NetworkFailure().toDisplayMessage());
  });
}
