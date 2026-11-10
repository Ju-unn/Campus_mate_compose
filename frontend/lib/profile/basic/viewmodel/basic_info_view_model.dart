import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/router/onboarding_step_listenable_provider.dart';
import 'package:campus_mate/profile/basic/model/data/basic_info_submission.dart';
import 'package:campus_mate/profile/basic/model/data/mbti_poles.dart';
import 'package:campus_mate/profile/basic/model/data/phone_code_sent.dart';
import 'package:campus_mate/profile/basic/model/repository/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/basic/viewmodel/basic_info_ui_state.dart';
import 'package:campus_mate/profile/basic/viewmodel/phone_verify_ui_state.dart';
import 'package:campus_mate/profile/onboarding/viewmodel/onboarding_blocked.dart';
import 'package:campus_mate/profile/onboarding/viewmodel/revisit_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final basicInfoViewModelProvider = NotifierProvider<BasicInfoViewModel, BasicInfoUiState>(
  BasicInfoViewModel.new,
);

/// `_copyWith` 에서 "이 필드는 건드리지 않는다" 를 뜻하는 표식(SchoolInfoViewModel 과 같은 패턴).
const Object _keep = Object();

/// 화면이 보는 "지금". 나이 하한과 휴대폰 인증번호의 남은 시간을 센다 — 테스트가 올해 · 시각을 고정할 수 있게 갈아끼운다
/// (`verifyCodeNowProvider` 와 같은 방식).
final basicInfoNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 기본 정보 화면(DESIGN.md 화면 04-1)의 흐름을 맡는다.
class BasicInfoViewModel extends Notifier<BasicInfoUiState> {
  Timer? _debounce;

  /// 휴대폰 인증번호의 남은 시간을 1초마다 다시 센다. 마감 시각은 서버가 준 초로 잡는다 — 앱이 잠든 사이에도 시각 기준이라 어긋나지 않는다.
  Timer? _clock;
  DateTime? _codeDeadline;
  DateTime? _resendDeadline;

  @override
  BasicInfoUiState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _clock?.cancel();
    });
    // 이 뷰모델은 앱이 켜진 동안 살아 있다(autoDispose 아님). 화면이 사라지거나 가려지면(듣는 쪽이 없으면) 1초 시계를 멈추고,
    // 다시 보이면 마감 시각으로 다시 센다 — 자리를 비운 동안 흐른 시간도 빠진다. 생명 주기 콜백 안에서는 ref · state 를 못 쓰므로
    // 다시 세기는 콜백이 끝난 뒤(마이크로태스크)에 한다.
    ref.onCancel(_pauseClock);
    ref.onResume(() => scheduleMicrotask(() {
          if (ref.mounted) _startClock();
        }));
    final drafts = ref.read(draftStoreProvider);
    listenSelf((previous, next) => _saveDraft(drafts, previous, next));
    final initial = _initialState(drafts, ref.read(basicInfoNowProvider)().year);
    _recheckRestoredNickname(initial.nicknameInput);
    return initial;
  }

  /// 복원한 닉네임도 형식 · 중복 안내를 다시 받는다 — 판정 결과는 저장하지 않았다.
  /// 빈 칸으로 열면(복원할 값이 없으면) 예전처럼 아무것도 걸지 않는다.
  void _recheckRestoredNickname(String nickname) {
    if (nickname.isEmpty) {
      return;
    }
    _scheduleNicknameCheck(nickname);
  }

  /// 처음 상태를 정하는 단 한 곳이다. 폰에 남긴 값 > (뒤로가기로 돌아왔으면) 서버 값 > 빈 값.
  BasicInfoUiState _initialState(DraftStore drafts, int thisYear) {
    final restored = drafts.read(DraftScreen.basicInfo, (data) => BasicInfoUiState.fromDraft(data, thisYear: thisYear));
    final saved = revisitProfile(ref);
    return restored ??
        (saved == null ? BasicInfoUiState(thisYear: thisYear) : BasicInfoUiState.fromProfile(saved, thisYear: thisYear));
  }

  /// 값이 바뀔 때마다 남긴다(저장소가 디바운스한다). 처음 상태(복원한 값 그대로)는 다시 쓰지 않고,
  /// 끝낸 단계는 서버에 있으니 남기지 않는다.
  void _saveDraft(DraftStore drafts, BasicInfoUiState? previous, BasicInfoUiState next) {
    if (previous == null || next.completed) {
      return;
    }
    // 남길 값이 그대로면 다시 쓰지 않는다 — 인증번호 시계가 1초마다 상태를 바꾸는데, 그때마다 쓰면 저장소의 디바운스가 계속 밀린다.
    final draft = next.toDraft();
    if (previous.toDraft().toString() == draft.toString()) {
      return;
    }
    drafts.write(DraftScreen.basicInfo, draft);
  }

  void changeNickname(String value) {
    // 입력이 바뀌는 순간 지난 판정은 지운다 — 다 지운 값에 "사용할 수 있어요" 가 남아 있으면 안 된다.
    state = _copyWith(nicknameInput: value, nicknameCheck: NicknameCheck.none);
    _scheduleNicknameCheck(value);
  }

  void _scheduleNicknameCheck(String value) {
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
  /// 번호(숫자)가 바뀌면 보낸 인증번호 · 오류 · 시계를 모두 지운다(②로). 하이픈만 다시 그린 같은 번호는 그대로 둔다.
  void changePhoneNumber(String value) {
    if (value.replaceAll(RegExp(r'\D'), '') == state.phoneDigits) {
      state = _copyWith(phoneNumberInput: value);
      return;
    }
    _stopClock();
    state = _copyWith(phoneNumberInput: value, phoneVerify: const PhoneVerifyUiState());
  }

  /// "번호 바꾸기"(⑥ → ②): 인증을 지우고 번호 칸을 연다 — 다시 인증해야 "다음" 이 켜진다.
  void changePhoneAgain() {
    _stopClock();
    state = _copyWith(phoneVerify: const PhoneVerifyUiState());
  }

  /// 인증번호 받기 · 다시 받기. 보내는 동안(⑩) 다시 불러도 한 번만 간다.
  Future<void> sendCode() async {
    if (!state.canSendCode) {
      return;
    }
    final digits = state.phoneDigits;
    _setPhone(state.phoneVerify.copyWith(isSending: true, error: null));
    final result = await ref.read(basicInfoRepositoryProvider).sendPhoneCode(digits);
    if (!ref.mounted || state.phoneDigits != digits) {
      return;
    }
    result.when(onSuccess: _codeSent, onFailure: _sendFailed);
  }

  /// 서버가 준 초로 마감 시각을 잡는다. already_sent 는 문자 없이 앞서 보낸 인증번호의 시간을 이어서 센다 — 적던 인증번호는 둔다.
  void _codeSent(PhoneCodeSent sent) {
    final now = _now();
    _codeDeadline = now.add(sent.expiresIn);
    _resendDeadline = now.add(sent.resendAfter);
    final current = state.phoneVerify;
    final continues = sent.alreadySent && current.step == PhoneVerifyStep.codeSent;
    _setPhone(
      continues
          ? current.copyWith(isSending: false, codeError: current.isCodeExpired ? null : current.codeError)
          : const PhoneVerifyUiState(step: PhoneVerifyStep.codeSent),
    );
    _startClock();
  }

  /// 받기가 막힌 이유를 번호 줄 아래 상태 줄로(⑦ ⑫ 잠시 후 · 010). 429 가 1분 안이면 다시 받기 시간만 센다.
  void _sendFailed(Failure failure) {
    final phone = state.phoneVerify.copyWith(isSending: false);
    switch (failure) {
      case ServerRejectedFailure() when failure.hasCode(_phoneNumberInvalidCode):
        _stopClock();
        state = _copyWith(
          rejectedPhoneDigits: state.phoneDigits,
          phoneVerify: const PhoneVerifyUiState(error: AppErrorFailure(AppError.phoneNotMobile)),
        );
      case ServerRejectedFailure() when failure.hasCode(_phoneNumberInUseCode):
        _stopClock();
        _setPhone(const PhoneVerifyUiState(error: AppErrorFailure(AppError.phoneInUse)));
      case RateLimitedFailure(:final retryAfterSeconds?) when retryAfterSeconds <= _shortWaitSeconds:
        _resendDeadline = _now().add(Duration(seconds: retryAfterSeconds));
        // 인증번호 줄이 없으면(첫 받기) 다시 받기 글자가 없다 — 받기 버튼이 왜 꺼졌는지 상태 줄로 알린다.
        _setPhone(phone.copyWith(error: phone.step == PhoneVerifyStep.idle ? const AppErrorFailure(AppError.tryLater) : null));
        _startClock();
      // 오늘 한도(자정까지 몇 시간)는 1초마다 셀 것이 없다 — 시계를 멈추고 받기를 끈 채 둔다. 번호를 고치면 풀린다(서버가 다시 본다).
      case RateLimitedFailure(retryAfterSeconds: _?):
        _stopClock();
        _setPhone(const PhoneVerifyUiState(error: AppErrorFailure(AppError.phoneDailyLimit)));
      case RateLimitedFailure() || ServerUnavailableFailure():
        _setPhone(phone.copyWith(error: const AppErrorFailure(AppError.tryLater)));
      default:
        _setPhone(phone.copyWith(error: failure));
    }
  }

  /// 인증번호 칸이 바뀔 때. 6자리가 되면 바로 한 번 확인한다(⑪). 고치면 지난 오류는 걷는다.
  Future<void> changeCode(String value) async {
    final phone = state.phoneVerify;
    if (phone.isVerifying || phone.isCodeExpired || phone.isCodeLocked) {
      return;
    }
    _setPhone(phone.copyWith(codeInput: value, codeError: null));
    if (value.length == verificationCodeLength) {
      await verifyCode();
    }
  }

  /// 인증번호 확인. 6자리가 아니거나 확인 중이면 보내지 않는다 — 서버는 6자리 숫자가 아니면 422 다.
  Future<void> verifyCode() async {
    final phone = state.phoneVerify;
    if (!phone.canVerify) {
      return;
    }
    final digits = state.phoneDigits;
    _setPhone(phone.copyWith(isVerifying: true, codeError: null));
    final result = await ref.read(basicInfoRepositoryProvider).verifyPhoneCode(digits, phone.codeInput);
    if (!ref.mounted || state.phoneDigits != digits) {
      return;
    }
    result.when(onSuccess: (_) => _verified(digits), onFailure: _verifyFailed);
  }

  void _verified(String digits) {
    _stopClock();
    _setPhone(PhoneVerifyUiState(step: PhoneVerifyStep.verified, verifiedDigits: digits));
  }

  void _verifyFailed(Failure failure) {
    final phone = state.phoneVerify.copyWith(isVerifying: false);
    switch (failure) {
      case ServerRejectedFailure(:final remainingAttempts?) when failure.hasCode(_codeMismatchCode):
        _setPhone(phone.copyWith(codeError: PhoneCodeMismatchFailure(remainingAttempts)));
      case ServerRejectedFailure() when failure.hasCode(_codeLockedCode):
        _setPhone(phone.copyWith(isCodeLocked: true, codeError: const AppErrorFailure(AppError.phoneCodeLocked)));
      case ServerRejectedFailure() when failure.hasCode(_codeExpiredCode):
        _codeDeadline = null;
        _setPhone(phone.copyWith(codeSecondsLeft: 0, codeError: const AppErrorFailure(AppError.phoneCodeExpired)));
      case ServerRejectedFailure() when failure.hasCode(_phoneNumberInvalidCode):
        _stopClock();
        state = _copyWith(
          rejectedPhoneDigits: state.phoneDigits,
          phoneVerify: const PhoneVerifyUiState(error: AppErrorFailure(AppError.phoneNotMobile)),
        );
      default:
        _setPhone(phone.copyWith(codeError: failure));
    }
  }

  void _setPhone(PhoneVerifyUiState phone) => state = _copyWith(phoneVerify: phone);

  DateTime _now() => ref.read(basicInfoNowProvider)();

  /// 마감 시각에서 남은 초를 다시 세고, 아직 셀 것이 남았으면 1초 시계를 돌린다.
  void _startClock() {
    if (_codeDeadline == null && _resendDeadline == null) {
      return;
    }
    _tick();
    final phone = state.phoneVerify;
    if (phone.codeSecondsLeft > 0 || phone.resendSecondsLeft > 0) {
      _clock ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  void _stopClock() {
    _pauseClock();
    _codeDeadline = null;
    _resendDeadline = null;
  }

  /// 시계만 멈춘다 — 마감 시각은 남겨 두어 다시 보일 때([_startClock]) 이어서 센다.
  void _pauseClock() {
    _clock?.cancel();
    _clock = null;
  }

  /// 남은 초를 마감 시각에서 다시 센다. 인증 시간이 0 이 되면 ⑤ 시간 지남(잠김 · 확인 중이 아닐 때). 둘 다 끝나면 시계를 멈춘다.
  void _tick() {
    final now = _now();
    var phone = state.phoneVerify.copyWith(
      codeSecondsLeft: _secondsUntil(_codeDeadline, now),
      resendSecondsLeft: _secondsUntil(_resendDeadline, now),
    );
    if (phone.isCodeExpired && !phone.isCodeLocked && !phone.isVerifying) {
      phone = phone.copyWith(codeError: const AppErrorFailure(AppError.phoneCodeExpired));
    }
    // 다시 받기 대기가 막 끝났다 — 1분 제한으로 첫 받기가 막혀 띄운 "잠시 후" 줄을 걷는다(받기가 다시 켜진다).
    // 대기가 도는 동안 상태 줄에 있을 수 있는 오류는 그 줄뿐이다(다른 오류는 대기 없이 띄우거나 시계를 멈춘다).
    if (state.phoneVerify.resendSecondsLeft > 0 && phone.resendSecondsLeft == 0) {
      phone = phone.copyWith(error: null);
    }
    if (phone.codeSecondsLeft == 0 && phone.resendSecondsLeft == 0) {
      _pauseClock();
    }
    _setPhone(phone);
  }

  static int _secondsUntil(DateTime? deadline, DateTime now) {
    if (deadline == null) {
      return 0;
    }
    final millis = deadline.difference(now).inMilliseconds;
    return millis <= 0 ? 0 : (millis + 999) ~/ 1000;
  }

  /// 서버 429 의 남은 초가 이 안이면 같은 번호 1분 제한이다 — 다시 받기 시간만 센다. 넘으면 오늘 한도(⑫).
  static const int _shortWaitSeconds = 60;
  void changeGender(String value) => state = _copyWith(gender: value);
  /// 같은 축의 다른 극은 자동으로 꺼진다 — 축마다 하나만 고른다.
  void toggleMbtiPole(String pole) {
    state = _copyWith(mbtiPoles: MbtiPoles.toggle(state.mbtiPoles, pole), isMbtiUnknown: false);
  }

  void toggleMbtiUnknown() {
    state = _copyWith(mbtiPoles: const {}, isMbtiUnknown: !state.isMbtiUnknown);
  }

  Future<void> submit() async {
    if (!state.canSubmit) {
      return;
    }
    // 지난 저장의 completed 를 내린다 — 되돌아와 다시 저장하다 실패하면 다음 화면으로 넘어가면 안 된다.
    state = _copyWith(isSubmitting: true, error: null, completed: false);
    state = await _submittedState();
    _discardDraftIfCompleted();
    _refreshOnboardingStepIfCompleted();
  }

  /// 단계를 끝냈으면 이 화면의 임시 저장 값을 지운다 — 다음에 다시 열 일이 없다.
  void _discardDraftIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(draftStoreProvider).clear(DraftScreen.basicInfo));
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
      reportIfOnboardingBlocked(ref, result);
      return _stateFromResult(result);
    } catch (_) {
      return _copyWith(isSubmitting: false, error: const UnknownFailure());
    }
  }

  BasicInfoUiState _stateFromResult(Result<void> result) {
    return result.when(
      onSuccess: (_) => _copyWith(isSubmitting: false, completed: true),
      onFailure: _stateFromFailure,
    );
  }

  /// 서버 422 `phone_number_invalid` 는 버튼 위가 아니라 번호 칸 아래에 띄운다(앱 규칙에 걸린 것과 같은 자리 · 문구).
  /// 문구가 아니라 code 로 가른다 — 서버가 문구를 고쳐도 자리가 바뀌지 않게.
  BasicInfoUiState _stateFromFailure(Failure failure) {
    if (failure is ServerRejectedFailure && failure.hasCode(_phoneNumberInvalidCode)) {
      return _copyWith(isSubmitting: false, rejectedPhoneDigits: state.phoneDigits);
    }
    // 인증이 30분을 넘겼거나 이미 쓰였다 — ⑤ 처럼 인증번호를 다시 받게 한다(대장 결정 11-10).
    if (failure is ServerRejectedFailure && failure.hasCode(_phoneNotVerifiedCode)) {
      _stopClock();
      return _copyWith(
        isSubmitting: false,
        phoneVerify: const PhoneVerifyUiState(
          step: PhoneVerifyStep.codeSent,
          codeError: AppErrorFailure(AppError.phoneCodeExpired),
        ),
      );
    }
    if (failure is ServerRejectedFailure && failure.hasCode(_phoneNumberInUseCode)) {
      _stopClock();
      return _copyWith(
        isSubmitting: false,
        phoneVerify: const PhoneVerifyUiState(error: AppErrorFailure(AppError.phoneInUse)),
      );
    }
    return _copyWith(isSubmitting: false, error: failure);
  }

  /// 서버 `POST /profile-onboarding/basic-info` 422 본문의 `code`(가입용 번호 규칙에 걸림).
  static const String _phoneNumberInvalidCode = 'phone_number_invalid';

  /// 휴대폰 문자 인증의 서버 code(PR #694 `errors.py` CODE_PHONE_*). 문구가 아니라 code 로 가른다.
  static const String _phoneNumberInUseCode = 'phone_number_in_use';
  static const String _phoneNotVerifiedCode = 'phone_not_verified';
  static const String _codeMismatchCode = 'phone_code_mismatch';
  static const String _codeLockedCode = 'phone_code_locked';
  static const String _codeExpiredCode = 'phone_code_expired';

  void _refreshOnboardingStepIfCompleted() {
    if (!state.completed) {
      return;
    }
    unawaited(ref.read(onboardingStepListenableProvider).stepSaved());
  }

  BasicInfoUiState _copyWith({
    String? nicknameInput,
    NicknameCheck? nicknameCheck,
    String? birthYearInput,
    String? heightInput,
    String? phoneNumberInput,
    Object? rejectedPhoneDigits = _keep,
    PhoneVerifyUiState? phoneVerify,
    String? gender,
    Set<String>? mbtiPoles,
    bool? isMbtiUnknown,
    bool? isSubmitting,
    Object? error = _keep,
    bool? completed,
  }) {
    return BasicInfoUiState(
      thisYear: state.thisYear,
      nicknameInput: nicknameInput ?? state.nicknameInput,
      nicknameCheck: nicknameCheck ?? state.nicknameCheck,
      birthYearInput: birthYearInput ?? state.birthYearInput,
      heightInput: heightInput ?? state.heightInput,
      phoneNumberInput: phoneNumberInput ?? state.phoneNumberInput,
      rejectedPhoneDigits:
          identical(rejectedPhoneDigits, _keep) ? state.rejectedPhoneDigits : rejectedPhoneDigits as String?,
      phoneVerify: phoneVerify ?? state.phoneVerify,
      gender: gender ?? state.gender,
      mbtiPoles: mbtiPoles ?? state.mbtiPoles,
      isMbtiUnknown: isMbtiUnknown ?? state.isMbtiUnknown,
      isSubmitting: isSubmitting ?? state.isSubmitting,
      error: identical(error, _keep) ? state.error : error as Failure?,
      completed: completed ?? state.completed,
    );
  }
}
