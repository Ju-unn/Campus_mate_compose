import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/model/onboarding_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/fake_avatar_repository.dart';
import '../model/fake_onboarding_repository.dart';

const _url = 'https://x.supabase.co/storage/v1/object/public/avatars/aa/avatar.png';

void main() {
  late FakeAvatarRepository repository;
  late FakeOnboardingRepository onboardingRepository;
  late ProviderContainer container;
  late DateTime now;

  setUp(() {
    repository = FakeAvatarRepository();
    onboardingRepository = FakeOnboardingRepository();
    now = DateTime(2026, 9, 26, 12);
    container = ProviderContainer(
      overrides: [
        avatarRepositoryProvider.overrideWithValue(repository),
        onboardingRepositoryProvider.overrideWithValue(onboardingRepository),
        avatarGenerationNowProvider.overrideWithValue(() => now),
      ],
    );
  });

  tearDown(() => container.dispose());

  AvatarGenerationViewModel viewModel() =>
      container.read(avatarGenerationViewModelProvider.notifier);

  AvatarGenerationUiState state() => container.read(avatarGenerationViewModelProvider);

  test('등록하면 만드는 중이 되고 04-3 을 붙잡지 않는다', () async {
    // 서버는 202 pending 을 바로 준다 — 여기서 그림을 기다리지 않는다.
    final blocking = await viewModel().generate();

    expect(blocking, isNull);
    expect(state().status, AvatarGenerationStatus.generating);
    expect(repository.generateCount, 1);
  });

  test('만드는 중에 또 누르면 저장소를 다시 부르지 않는다', () async {
    // 돈이 나가는 길은 앱과 서버 양쪽에서 막는다(D14 운영 로그 — 59초 사이에 유료 호출 2회).
    final vm = viewModel();
    await vm.generate();
    await vm.generate();

    expect(repository.generateCount, 1);
  });

  test('응답을 못 받으면 붙잡지 않고 넘어간다', () async {
    // 서버에는 이미 작업이 있을 수 있다 — 결과는 05-12 가 보여 준다.
    repository.nextResult = const FailureResult(NetworkFailure());

    expect(await viewModel().generate(), isNull);
    expect(state().status, AvatarGenerationStatus.generating);
  });

  test('이미 아바타가 있다고 답하면 붙잡지 않고 넘어간다', () async {
    repository.nextResult = const FailureResult(ServerRejectedFailure('아바타는 한 번만 만들 수 있어요'));

    expect(await viewModel().generate(), isNull);
  });

  test('원본 사진이 없다고 답하면 그 자리에 오류를 보여 준다', () async {
    // 사람이 고칠 수 있는 오류다 — 넘어가면 고칠 자리가 없다.
    repository.nextResult = const FailureResult(ServerRejectedFailure('아바타 원본 사진을 먼저 골라 주세요'));

    final blocking = await viewModel().generate();

    expect(blocking, '아바타 원본 사진을 먼저 골라 주세요');
    expect(state().status, AvatarGenerationStatus.failed);
  });

  test('큐 설정이 안 된 서버(503)면 넘어가지 않는다', () async {
    // 넘어가 봐야 결과 화면이 빈다.
    repository.nextResult = const FailureResult(ServerUnavailableFailure());

    expect(await viewModel().generate(), isNotNull);
    expect(state().status, AvatarGenerationStatus.failed);
  });

  test('상태 조회가 ready 를 주면 그림 주소를 그대로 들고 완료로 넘어간다', () async {
    repository.nextResult = const Success(AvatarReady(_url));

    await viewModel().refreshStatus();

    expect(state().status, AvatarGenerationStatus.ready);
    expect(state().avatarUrl, _url);
    // 결과가 나왔다고 자동으로 넘어가지 않는다 — 넘어가는 시점은 사람이 "다음" 으로 정한다(05-12c).
    expect(onboardingRepository.fetchCount, 0);
  });

  test('다음을 누르면 그때 다음 단계를 묻는다', () async {
    await viewModel().goToNextStep();

    expect(onboardingRepository.fetchCount, 1);
  });

  test('만드는 중이면 5초 뒤 다시 물어보고, 끝나면 그만 묻는다', () async {
    repository.statusResults.addAll(const [
      Success(AvatarPending()),
      Success(AvatarReady(_url)),
    ]);

    await viewModel().refreshStatus();
    expect(state().status, AvatarGenerationStatus.generating);
    expect(repository.statusCount, 1);

    await Future<void>.delayed(const Duration(seconds: 6));

    expect(state().status, AvatarGenerationStatus.ready);
    expect(repository.statusCount, 2);

    // 끝났으면 타이머를 끊는다 — 안 끊으면 화면을 떠난 뒤에도 계속 묻는다.
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(repository.statusCount, 2);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('화면을 떠나면 그만 묻는다', () async {
    // 뷰모델은 화면보다 오래 산다 — 안 끊으면 다른 화면에서도 5초마다 계속 묻는다.
    repository.nextResult = const Success(AvatarPending());
    final vm = viewModel();

    await vm.refreshStatus();
    expect(repository.statusCount, 1);

    vm.stopPolling();
    await Future<void>.delayed(const Duration(seconds: 6));

    expect(repository.statusCount, 1);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('10분이 지나면 그만 묻고 다시 만들기를 띄운다', () async {
    // 서버도 이 시점부터는 실패로 본다(STALE_PENDING_AFTER 와 같은 값).
    repository.nextResult = const Success(AvatarPending());
    final vm = viewModel();

    await vm.refreshStatus();
    expect(state().status, AvatarGenerationStatus.generating);

    now = now.add(const Duration(minutes: 11));
    await vm.refreshStatus();

    expect(state().status, AvatarGenerationStatus.failed);
    expect(state().canRetry, isTrue);
  });

  test('한 번 조회에 실패해도 화면을 실패로 바꾸지 않는다', () async {
    repository.statusResults.addAll(const [
      Success(AvatarPending()),
      FailureResult(NetworkFailure()),
      Success(AvatarReady(_url)),
    ]);
    final vm = viewModel();

    await vm.refreshStatus();
    await Future<void>.delayed(const Duration(seconds: 6));

    expect(state().status, AvatarGenerationStatus.generating);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('첫 조회가 아예 실패해도 5초 뒤에 다시 묻는다', () async {
    // 실패하면 상태가 idle 로 남는데, 화면은 idle 을 만드는 중과 똑같이 그린다 —
    // 여기서 타이머를 끊으면 뒤로 갈 곳도 없는 화면에서 도는 표시가 영영 돈다.
    repository.statusResults.addAll(const [
      FailureResult(NetworkFailure()),
      Success(AvatarReady(_url)),
    ]);
    final vm = viewModel();

    await vm.refreshStatus();
    expect(state().status, AvatarGenerationStatus.idle);

    await Future<void>.delayed(const Duration(seconds: 6));

    expect(repository.statusCount, 2);
    expect(state().status, AvatarGenerationStatus.ready);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('다시 만들기를 누른 뒤에도 5초마다 다시 묻는다', () async {
    // 재등록도 202 pending 이라 결과는 나중에 온다 — 여기서 타이머를 다시 안 걸면 영영 돈다.
    repository.nextResult = const Success(AvatarPending());
    final vm = viewModel();

    await vm.retry();
    expect(repository.statusCount, 1);

    await Future<void>.delayed(const Duration(seconds: 6));

    expect(repository.statusCount, 2);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('fallback 이면 그림과 서버가 준 하트 수를 같이 들고 보상 안내를 켠다', () async {
    repository.nextResult = const Success(AvatarFallback(_url, 10));

    await viewModel().refreshStatus();

    final result = state();
    expect(result.status, AvatarGenerationStatus.fallback);
    expect(result.avatarUrl, _url);
    expect(result.showCompensationDialog, isTrue);
    expect(result.compensationHearts, 10);
  });

  test('아직 한 번도 안 만든 사람에게는 다시 만들기를 띄운다', () async {
    // 상태 조회는 none 을 실패와 같게 돌려준다 — 자동 등록은 서버도 앱도 하지 않는다.
    repository.nextResult = const Success(AvatarFailed());

    await viewModel().refreshStatus();

    expect(state().canRetry, isTrue);
    expect(repository.generateCount, 0);
  });

  group('화면 15 다시 만들기(15b regenerate)', () {
    test('등록하면 만드는 중이 되고 곧바로 상태를 묻는다', () async {
      // 재등록도 202 pending 이다 — 결과는 워커가 만든 뒤에 오니 여기서 폴링을 시작해야 한다.
      final message = await viewModel().regenerate();

      expect(message, isNull);
      expect(repository.regenerateCount, 1);
      expect(repository.generateCount, 0);
      expect(repository.statusCount, 1);
      expect(state().status, AvatarGenerationStatus.generating);
    });

    test('등록 뒤에도 5초마다 다시 묻는다', () async {
      final vm = viewModel();
      await vm.regenerate();
      expect(repository.statusCount, 1);

      await Future<void>.delayed(const Duration(seconds: 6));

      expect(repository.statusCount, 2);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('등록이 끝나기 전에 또 눌러도 유료 호출은 한 번이다', () async {
      // 돈이 나가는 길이다(D14 — 59초 사이 유료 호출 2회). 앱 쪽 가드가 generate 와 같아야 한다.
      repository.generateGate = Completer<void>();
      final vm = viewModel();

      final first = vm.regenerate();
      // 두 번째를 기다리기 전에 문을 연다 — 가드가 없으면 교착(시간 초과) 대신 "2회" 로 바로 떨어진다.
      final second = vm.regenerate();
      repository.generateGate!.complete();
      await first;

      expect(await second, isNull);
      expect(repository.regenerateCount, 1);
    });

    test('응답만 놓치면(네트워크) 실패로 두지 않고 상태를 물어 이어 간다', () async {
      // 서버는 이미 큐에 넣었을 수 있다 — 여기서 실패로 두면 15-3 "하트는 차감되지 않았어요" 가 거짓이 된다.
      repository.nextResult = const FailureResult(NetworkFailure());

      final message = await viewModel().regenerate();

      expect(message, isNull);
      expect(state().status, AvatarGenerationStatus.generating);
      expect(repository.statusCount, 1);
    });

    test('하트가 모자라다고(402) 답하면 그 문구를 돌려주고 상태를 묻지 않는다', () async {
      // 시트를 연 사이에 잔액이 줄었을 때. 화면 15 가 이 문구를 토스트로 보여 준다.
      repository.nextResult = const FailureResult(ServerRejectedFailure('하트가 모자라요'));

      final message = await viewModel().regenerate();

      expect(message, '하트가 모자라요');
      expect(state().status, AvatarGenerationStatus.failed);
      expect(state().errorMessage, '하트가 모자라요');
      expect(repository.statusCount, 0);
    });

    test('등록이 실패하면 실패 문구를 돌려준다', () async {
      repository.nextResult = const FailureResult(ServerUnavailableFailure());

      final message = await viewModel().regenerate();

      expect(message, '잠시 뒤 다시 시도해 주세요');
      expect(state().canRetry, isTrue);
    });
  });

  test('다시 만들기가 실패해도 상태를 다시 물어 화면에 갇히지 않는다', () async {
    // 앱이 응답을 놓쳤을 뿐 서버에는 이미 아바타가 있는 경우가 있다 — 그 답이 상태 조회로 돌아온다.
    repository.nextResult = const FailureResult(UnknownFailure());
    repository.statusResults.add(const Success(AvatarReady(_url)));

    await viewModel().retry();

    expect(repository.statusCount, 1);
    expect(state().status, AvatarGenerationStatus.ready);
  });
}
