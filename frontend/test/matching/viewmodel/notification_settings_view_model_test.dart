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
}
