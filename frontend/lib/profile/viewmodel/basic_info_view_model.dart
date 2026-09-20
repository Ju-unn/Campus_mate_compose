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

/// 기본 정보 화면(DESIGN.md 화면 04-1)의 흐름을 맡는다.
class BasicInfoViewModel extends Notifier<BasicInfoUiState> {
  Timer? _debounce;

  @override
  BasicInfoUiState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const BasicInfoUiState();
  }

  void changeNickname(String value) {
    state = _copyWith(nicknameInput: value, nicknameError: null);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _checkNickname(value));
  }

  Future<void> _checkNickname(String value) async {
    if (!RegExp(r'^[가-힣a-zA-Z]{2,5}$').hasMatch(value)) {
      return;
    }
    final repository = ref.read(basicInfoRepositoryProvider);
    final result = await repository.checkNicknameAvailability(value);
    if (!ref.mounted || state.nicknameInput != value) {
      return; // 조회가 끝나기 전에 입력이 또 바뀌었으면 낡은 결과를 반영하지 않는다.
    }
    result.when(
      onSuccess: (available) => state = _copyWith(nicknameError: available ? null : '이미 있는 닉네임이에요'),
      onFailure: (_) {},
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
        phoneNumber: state.phoneNumberInput,
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
    Object? nicknameError = _keep,
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
      nicknameInput: nicknameInput ?? state.nicknameInput,
      nicknameError: identical(nicknameError, _keep) ? state.nicknameError : nicknameError as String?,
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
