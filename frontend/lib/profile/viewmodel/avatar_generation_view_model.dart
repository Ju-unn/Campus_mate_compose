import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/avatar_generation_outcome.dart';
import 'package:campus_mate/profile/model/avatar_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final avatarGenerationViewModelProvider =
    NotifierProvider<AvatarGenerationViewModel, AvatarGenerationUiState>(AvatarGenerationViewModel.new);

/// 결과 화면이 "다 됐나요" 를 묻는 간격.
const _pollInterval = Duration(seconds: 5);

/// 그만 묻는 시각. 서버의 `STALE_PENDING_AFTER`(avatars.py)와 **같은 10분**이다 —
/// 어긋나면 화면은 아직 기다리는데 서버는 이미 실패로 보는 구간이 생긴다.
///
/// 값은 같지만 **재기 시작하는 기준은 다르다** — 앱은 이 화면에서 처음 물어본 시각부터,
/// 서버는 행의 `created_at` 부터다. 화면을 늦게 열면 앱이 그만큼 더 기다린다(기다리는 쪽이라 안전하다).
const _pollLimit = Duration(minutes: 10);

/// 폴링 상한을 세는 시계. 테스트가 갈아끼운다(`verifyCodeNowProvider` 와 같은 방식).
final avatarGenerationNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 아바타 작업 등록(04-3)과 결과 보기(05-12 계열)의 흐름을 맡는다.
///
/// **두 화면이 같은 뷰모델을 쓴다** — 04-3 은 등록만 하고 넘어가고, 05-12 는 결과를 본다.
class AvatarGenerationViewModel extends Notifier<AvatarGenerationUiState> {
  Timer? _poll;
  DateTime? _pollStartedAt;

  @override
  AvatarGenerationUiState build() {
    ref.onDispose(_stopPolling);
    return const AvatarGenerationUiState();
  }

  /// 작업을 등록한다(서버는 202 를 바로 준다 — 그림을 기다리지 않는다).
  ///
  /// 돌려주는 값은 **04-3 에 붙잡아 두고 보여 줄 오류**다. `null` 이면 그냥 다음 질문으로 넘어가도 된다.
  /// 04-3(업로드 직후)과 05-12b("다시 만들기")가 같은 함수를 부르므로 **진행 중 가드도 여기** 둔다 —
  /// 화면마다 두면 한쪽을 빠뜨리고, 그 길로 유료 호출이 두 번 나간다(D14 운영 로그, 59초 사이 2회).
  Future<String?> generate() async {
    if (state.isGenerating) {
      return null;
    }
    state = const AvatarGenerationUiState(status: AvatarGenerationStatus.generating);
    final result = await ref.read(avatarRepositoryProvider).generateAvatar();
    return result.when(
      onSuccess: (outcome) {
        state = _fromOutcome(outcome);
        return null;
      },
      onFailure: _blockingMessage,
    );
  }

  /// "다시 만들기"(05-12b). 등록한 **뒤에 상태를 다시 묻는다** — 두 가지를 같이 해결한다.
  /// ① 재등록도 202 pending 이라 결과는 나중에 온다. 여기서 안 물으면 타이머가 없어 영영 돈다.
  /// ② 앱이 응답을 놓쳤을 뿐 서버에는 이미 아바타가 있는 경우, 그 답이 여기서 돌아온다.
  Future<void> retry() async {
    await generate();
    await refreshStatus();
  }

  /// 결과 화면에 들어올 때 한 번, 그 뒤 만드는 중이면 [_pollInterval] 마다.
  Future<void> refreshStatus() async {
    final result = await ref.read(avatarRepositoryProvider).fetchAvatarStatus();
    result.when(
      // 한 번 못 물어봤다고 화면을 실패로 바꾸지 않는다 — 다음 차례에 다시 묻는다.
      onSuccess: (outcome) => state = _fromOutcome(outcome),
      onFailure: (_) {},
    );
    // 조회가 통째로 실패하면 상태가 idle 로 남는다 — 그 경우도 **계속 물어야** 한다.
    // 화면이 도는 표시를 그리는 동안은 묻는 쪽도 살아 있어야 한다(`isWaiting` 이 그 약속이다).
    if (state.isWaiting) {
      _scheduleNextPoll();
      return;
    }
    _stopPolling();
  }

  /// 결과(05-12c·05-12d)를 다 본 사람이 "다음"을 눌렀을 때. **여기서만** 다음 단계를 다시 묻는다 —
  /// 결과를 받은 순간 자동으로 부르면 라우터가 06-1 로 화면을 바꿔 버려서,
  /// 애써 만든 아바타도 기본 아바타 보상 안내도 사람이 못 본다.
  Future<void> goToNextStep() => ref.read(onboardingStepListenableProvider).refresh();

  void _scheduleNextPoll() {
    final now = ref.read(avatarGenerationNowProvider)();
    _pollStartedAt ??= now;
    if (now.difference(_pollStartedAt!) >= _pollLimit) {
      // 서버도 이 시점부터는 실패로 본다. 화면은 "다시 만들기" 를 띄운다.
      _stopPolling();
      state = const AvatarGenerationUiState(status: AvatarGenerationStatus.failed);
      return;
    }
    _poll?.cancel();
    _poll = Timer(_pollInterval, refreshStatus);
  }

  /// 화면을 떠날 때 부른다. 이 뷰모델은 화면과 수명이 다르다(04-3 과 05-12 가 같이 쓴다) —
  /// 화면이 닫히는 것만으로는 안 끊겨서, 떠나는 쪽이 직접 끊어 준다.
  void stopPolling() => _stopPolling();

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
    _pollStartedAt = null;
  }

  AvatarGenerationUiState _fromOutcome(AvatarGenerationOutcome outcome) {
    return outcome.when(
      pending: () => const AvatarGenerationUiState(status: AvatarGenerationStatus.generating),
      ready: (url) => AvatarGenerationUiState(
        status: AvatarGenerationStatus.ready,
        avatarUrl: url,
      ),
      failed: () => const AvatarGenerationUiState(status: AvatarGenerationStatus.failed),
      fallback: (url, hearts) => AvatarGenerationUiState(
        status: AvatarGenerationStatus.fallback,
        avatarUrl: url,
        showCompensationDialog: true,
        compensationHearts: hearts,
      ),
    );
  }

  /// 등록이 실패했을 때 04-3 에 머물지(오류 문구) 그냥 넘어갈지(null) 를 고른다.
  ///
  /// **넘어가는 두 경우:** 응답을 못 받았거나(타임아웃·네트워크) 서버에 이미 아바타가 있을 때.
  /// 둘 다 서버에는 이미 아바타나 작업이 있어 여기 붙잡아 둘 이유가 없고, 결과는 05-12 가 보여 준다.
  /// 나머지(원본 사진 없음·큐 설정 안 됨 등)는 그 자리에서 알려 준다 — 앞은 사람이 고칠 수 있고,
  /// 뒤는 넘어가 봐야 결과 화면이 빈다.
  String? _blockingMessage(Failure failure) {
    if (failure is NetworkFailure || _isAlreadyCreated(failure)) {
      state = const AvatarGenerationUiState(status: AvatarGenerationStatus.generating);
      return null;
    }
    final message = failure.toDisplayMessage();
    state = AvatarGenerationUiState(status: AvatarGenerationStatus.failed, errorMessage: message);
    return message;
  }

  /// 서버가 "이미 만들었다"고 답한 것인지. 문구로 가른다 — 지금 계약에는 오류 **코드**가 없다
  /// (`backend/app/core/errors.py` `AVATAR_ALREADY_CREATED`). 코드가 생기면 여기부터 고친다.
  bool _isAlreadyCreated(Failure failure) =>
      failure is ServerRejectedFailure &&
      failure.toDisplayMessage() == '아바타는 한 번만 만들 수 있어요';
}
