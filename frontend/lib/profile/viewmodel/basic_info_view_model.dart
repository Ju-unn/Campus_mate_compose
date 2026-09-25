import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/model/basic_info_repository.dart';
import 'package:campus_mate/profile/model/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final basicInfoViewModelProvider = NotifierProvider<BasicInfoViewModel, BasicInfoUiState>(
  BasicInfoViewModel.new,
);

/// `_copyWith` 에서 "이 필드는 건드리지 않는다" 를 뜻하는 표식(SchoolInfoViewModel 과 같은 패턴).
const Object _keep = Object();

/// 화면이 보는 "지금". 나이 하한을 세는 데만 쓴다 — 테스트가 올해를 고정할 수 있게 갈아끼운다
/// (`verifyCodeNowProvider` 와 같은 방식).
final basicInfoNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 기본 정보 화면(DESIGN.md 화면 04-1)의 흐름을 맡는다.
class BasicInfoViewModel extends Notifier<BasicInfoUiState> {
  Timer? _debounce;

  @override
  BasicInfoUiState build() {
    ref.onDispose(() => _debounce?.cancel());
    return BasicInfoUiState(thisYear: ref.read(basicInfoNowProvider)().year);
  }

  void changeNickname(String value) {
    // 입력이 바뀌는 순간 지난 판정은 지운다 — 다 지운 값에 "사용할 수 있어요" 가 남아 있으면 안 된다.
    state = _copyWith(nicknameInput: value, nicknameCheck: NicknameCheck.none);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _checkNickname(value));
  }

  /// 디바운스가 끝나면 형식부터 보고, 통과한 값만 서버에 묻는다. 어느 쪽이든 결과를 화면에 남긴다 —
  /// 종전에는 형식이 안 맞으면 조용히 돌아가서 무엇이 잘못됐는지 아무 말도 없었다(2026-09-26 사용자 지적).
  Future<void> _checkNickname(String value) async {
    if (value.isEmpty) {
      return; // 아직 아무것도 안 쓴 칸과 같다 — 빈 칸에 빨간 글씨를 띄우지 않는다.
    }
    if (!BasicInfoUiState.nicknamePattern.hasMatch(value)) {
      state = _copyWith(nicknameCheck: NicknameCheck.invalid);
      return;
    }
    state = _copyWith(nicknameCheck: NicknameCheck.checking);
    final repository = ref.read(basicInfoRepositoryProvider);
    final result = await repository.checkNicknameAvailability(value);
    if (!ref.mounted || state.nicknameInput != value) {
      return; // 조회가 끝나기 전에 입력이 또 바뀌었으면 낡은 결과를 반영하지 않는다.
    }
    result.when(
      onSuccess: (available) =>
          state = _copyWith(nicknameCheck: available ? NicknameCheck.available : NicknameCheck.taken),
      // 확인 자체가 실패하면(네트워크) 아무 말도 하지 않는다 — 틀렸다고 단정할 근거가 없고, 제출 때 서버가 다시 본다.
      // 다만 도는 표시는 반드시 내린다. 안 내리면 "확인 중…" 이 영영 남는다.
      onFailure: (_) => state = _copyWith(nicknameCheck: NicknameCheck.none),
    );
  }

  void changeBirthYear(String value) => state = _copyWith(birthYearInput: value);
  void changeHeight(String value) => state = _copyWith(heightInput: value);
  void changePhoneNumber(String value) => state = _copyWith(phoneNumberInput: value);
  void changeGender(String value) => state = _copyWith(gender: value);
  /// 같은 축의 다른 극은 자동으로 꺼진다 — 축마다 하나만 고른다.
  void toggleMbtiPole(String pole) {
    final axis = BasicInfoUiState.mbtiAxes.firstWhere((axis) => axis.contains(pole));
    final poles = {...state.mbtiPoles}..removeAll(axis);
    if (!state.mbtiPoles.contains(pole)) {
      poles.add(pole);
    }
    state = _copyWith(mbtiPoles: poles, isMbtiUnknown: false);
  }

  void toggleMbtiUnknown() {
    state = _copyWith(mbtiPoles: const {}, isMbtiUnknown: !state.isMbtiUnknown);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    state = _copyWith(isSubmitting: true, errorMessage: null);
    state = await _submittedState();
    _refreshOnboardingStepIfCompleted();
  }

  Future<BasicInfoUiState> _submittedState() async {
    try {
      final repository = ref.read(basicInfoRepositoryProvider);
      final submission = BasicInfoSubmission(
        nickname: state.nicknameInput,
        birthYear: state.birthYear!,
        heightCm: state.heightCm!,
        phoneNumber: state.phoneDigits,
        gender: state.gender!,
        mbti: state.mbti,
      );
      final result = await repository.submit(submission);
      return _stateFromResult(result);
    } catch (_) {
      return _copyWith(isSubmitting: false, errorMessage: const UnknownFailure().toDisplayMessage());
    }
  }

  BasicInfoUiState _stateFromResult(Result<void> result) {
    return result.when(
      onSuccess: (_) => _copyWith(isSubmitting: false, completed: true),
      onFailure: (failure) => _copyWith(isSubmitting: false, errorMessage: failure.toDisplayMessage()),
    );
  }

  void _refreshOnboardingStepIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(onboardingStepListenableProvider).refresh());
  }

  BasicInfoUiState _copyWith({
    String? nicknameInput,
    NicknameCheck? nicknameCheck,
    String? birthYearInput,
    String? heightInput,
    String? phoneNumberInput,
    String? gender,
    Set<String>? mbtiPoles,
    bool? isMbtiUnknown,
    bool? isSubmitting,
    Object? errorMessage = _keep,
    bool? completed,
  }) {
    return BasicInfoUiState(
      thisYear: state.thisYear,
      nicknameInput: nicknameInput ?? state.nicknameInput,
      nicknameCheck: nicknameCheck ?? state.nicknameCheck,
      birthYearInput: birthYearInput ?? state.birthYearInput,
      heightInput: heightInput ?? state.heightInput,
      phoneNumberInput: phoneNumberInput ?? state.phoneNumberInput,
      gender: gender ?? state.gender,
      mbtiPoles: mbtiPoles ?? state.mbtiPoles,
      isMbtiUnknown: isMbtiUnknown ?? state.isMbtiUnknown,
      isSubmitting: isSubmitting ?? state.isSubmitting,
      errorMessage: identical(errorMessage, _keep) ? state.errorMessage : errorMessage as String?,
      completed: completed ?? state.completed,
    );
  }
}
