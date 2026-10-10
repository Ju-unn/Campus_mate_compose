import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/model/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/model/mbti_poles.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final basicInfoEditViewModelProvider =
    NotifierProvider.autoDispose<BasicInfoEditViewModel, BasicInfoEditUiState>(BasicInfoEditViewModel.new);

/// 서버가 닉네임 칸 탓으로 돌려주는 409 문구(backend `app/core/errors.py` NICKNAME_TAKEN · NICKNAME_CHANGE_TOO_SOON).
/// 앱은 상태코드를 못 보고 문구만 받으므로 문구로 자리를 가른다(`chat_errors.dart` 와 같은 방식).
const Set<String> _nicknameRejections = {'이미 있는 닉네임이에요', '닉네임은 30일에 한 번 바꿀 수 있어요'};

/// 서버 422(`errors.py` INVALID_INPUT) — 키 check(120~230) 위반이 이 문구로 온다.
const String _invalidInput = '입력한 값을 다시 확인해 주세요';

/// 칸 탓이 아닌 저장 실패 문구 — pen 15-6c `C3oV5u`(실패 종류와 상관없이 같다).
const String saveFailedMessage = '저장하지 못했어요. 잠시 후 다시 시도해 주세요';

/// 15-6 기본 정보 수정(pen `mhdYA` · 15-6-2 `ZuPTD`, 계획서 2026-09-28-me-profile.md A16 · 옛 A7). 닉네임 · 키 · MBTI · 종교 · 흡연 ·
/// 내 동물상 · 내 인상을 고친다. 출생연도 · 성별 · 학과는 잠금 행으로 보여 주기만 한다(10-10 사용자 결정).
///
/// 편집 모드. 열 때마다 서버 값으로 채운다 — autoDispose 라 닫으면 고치다 만 값이 남지 않는다(Review Focus 5).
/// 닉네임 형식 · 중복 확인은 04-1 과 같은 규칙 · 같은 시점(300ms 디바운스)이다. **바뀐 칸만** 보낸다 — 닉네임이 그대로면
/// 묻지도 보내지도 않는다. 저장이 끝나면 내 프로필을 다시 읽게 하고(invalidate) 15-5 로 돌아간다(N8 · B4).
class BasicInfoEditViewModel extends Notifier<BasicInfoEditUiState> {
  Timer? _debounce;

  /// 내 프로필을 watch 하지 않고 read 한다 — 저장 뒤 다시 읽혀도 고치던 값이 서버 값으로 되돌아가지 않게(15c 와 같다).
  @override
  BasicInfoEditUiState build() {
    ref.onDispose(() => _debounce?.cancel());
    final profile = ref.read(myProfileProvider).value?.when<MyProfile?>(onSuccess: (p) => p, onFailure: (_) => null);
    final height = profile?.heightCm?.toString() ?? '';
    return BasicInfoEditUiState(
      savedNickname: profile?.nickname ?? '',
      savedHeight: height,
      nicknameChangeableAt: profile?.nicknameChangeableAt,
      nicknameInput: profile?.nickname ?? '',
      heightInput: height,
      savedMbti: profile?.mbti,
      // MBTI 가 null 이면 "선택 안 함" 이다 — "모름" 칩이 켜진 채 열린다.
      mbtiPoles: MbtiPoles.fromCode(profile?.mbti),
      isMbtiUnknown: profile?.mbti == null,
      savedReligion: profile?.religion,
      religion: profile?.religion,
      savedIsSmoker: profile?.isSmoker,
      isSmoker: profile?.isSmoker,
      savedAnimalType: profile?.animalType,
      animalType: profile?.animalType,
      savedImpressionType: profile?.impressionType,
      impressionType: profile?.impressionType,
      birthYear: profile?.birthYear,
      gender: profile?.gender,
      major: profile?.major,
    );
  }

  /// 입력이 바뀌면 지난 판정과 서버 오류를 지운다. 지금 닉네임으로 되돌리면 묻지 않는다 — 내 닉네임이다.
  void changeNickname(String value) {
    state = state.copyWith(nicknameInput: value, nicknameCheck: NicknameCheck.none, nicknameRejection: null);
    _debounce?.cancel();
    if (value == state.savedNickname) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _checkNickname(value));
  }

  /// 04-1 `BasicInfoViewModel._checkNickname` 과 같다 — 형식부터 보고, 통과한 값만 서버에 묻는다(서버는 내 행을 빼고 본다).
  Future<void> _checkNickname(String value) async {
    if (value.isEmpty) {
      return; // 빈 칸에 빨간 글씨를 띄우지 않는다 — 저장은 형식 검사가 막는다.
    }
    if (!BasicInfoUiState.nicknamePattern.hasMatch(value)) {
      state = state.copyWith(nicknameCheck: NicknameCheck.invalid);
      return;
    }
    state = state.copyWith(nicknameCheck: NicknameCheck.checking);
    final result = await ref.read(basicInfoRepositoryProvider).checkNicknameAvailability(value);
    if (!ref.mounted || state.nicknameInput != value) {
      return; // 조회가 끝나기 전에 입력이 또 바뀌었으면 낡은 결과를 반영하지 않는다.
    }
    // 확인 자체가 실패하면(네트워크) 아무 말도 하지 않는다 — 저장 때 서버가 다시 본다(04-1 과 같다).
    state = state.copyWith(
      nicknameCheck: result.when(
        onSuccess: (available) => available ? NicknameCheck.available : NicknameCheck.taken,
        onFailure: (_) => NicknameCheck.none,
      ),
    );
  }

  void changeHeight(String value) => state = state.copyWith(heightInput: value, heightRejection: null);

  /// 아래 칸들은 저장 중에 바꾸지 못한다 — 보내는 값과 화면 값이 갈라지지 않게(닉네임 · 키 칸은 읽기 전용으로 막는다).
  void toggleMbtiPole(String pole) {
    if (state.isSubmitting) {
      return;
    }
    state = state.copyWith(mbtiPoles: MbtiPoles.toggle(state.mbtiPoles, pole), isMbtiUnknown: false);
  }

  void toggleMbtiUnknown() {
    if (state.isSubmitting) {
      return;
    }
    state = state.copyWith(mbtiPoles: const {}, isMbtiUnknown: !state.isMbtiUnknown);
  }

  void changeReligion(Religion value) {
    if (!state.isSubmitting) {
      state = state.copyWith(religion: value);
    }
  }

  void changeIsSmoker(bool value) {
    if (!state.isSubmitting) {
      state = state.copyWith(isSmoker: value);
    }
  }

  void changeAnimalType(AnimalType value) {
    if (!state.isSubmitting) {
      state = state.copyWith(animalType: value);
    }
  }

  void changeImpressionType(ImpressionType value) {
    if (!state.isSubmitting) {
      state = state.copyWith(impressionType: value);
    }
  }

  Future<void> save() async {
    if (!state.canSave) {
      return;
    }
    final nickname = state.isNicknameChanged ? state.nicknameInput : null;
    final heightCm = state.isHeightChanged ? state.heightCm : null;
    final mbti = state.isMbtiChanged ? state.mbtiCode : null;
    final appearance = state.isAppearanceChanged
        ? (animalType: state.animalType!, impressionType: state.impressionType!)
        : null;
    final sent = (
      nickname: nickname,
      heightCm: heightCm,
      mbti: mbti,
      clearMbti: state.isMbtiChanged && mbti == null,
      religion: state.isReligionChanged ? state.religion : null,
      isSmoker: state.isSmokerChanged ? state.isSmoker : null,
      appearance: appearance,
    );
    state = state.copyWith(isSubmitting: true, errorMessage: null);
    // 저장 중에 뒤로 나가도 끝까지 저장하고 15-5 를 다시 읽게 한다 — 그동안 autoDispose 가 버리지 않게 붙잡는다.
    final keepAlive = ref.keepAlive();
    try {
      final result = await ref.read(meRepositoryProvider).updateProfile(
            nickname: sent.nickname,
            heightCm: sent.heightCm,
            mbti: sent.mbti,
            clearMbti: sent.clearMbti,
            religion: sent.religion,
            isSmoker: sent.isSmoker,
            appearance: sent.appearance,
          );
      state = result.when(
        onSuccess: (_) => state.copyWith(isSubmitting: false, completed: true),
        onFailure: (failure) => _rejectedState(failure, sentHeight: heightCm != null),
      );
      if (state.completed) {
        ref.invalidate(myProfileProvider);
      }
    } finally {
      keepAlive.close();
    }
  }

  /// 실패 문구를 탓할 칸 아래로 보낸다(B5). 어느 칸 탓인지 모르는 실패(네트워크 등)는 04-1 처럼 버튼 위 저장 실패 문구다.
  BasicInfoEditUiState _rejectedState(Failure failure, {required bool sentHeight}) {
    final message = failure.toDisplayMessage();
    if (_nicknameRejections.contains(message)) {
      return state.copyWith(isSubmitting: false, nicknameRejection: message);
    }
    if (sentHeight && message == _invalidInput) {
      return state.copyWith(isSubmitting: false, heightRejection: message);
    }
    return state.copyWith(isSubmitting: false, errorMessage: saveFailedMessage);
  }
}

/// `copyWith` 에서 "이 칸은 그대로" 를 뜻하는 표식 — null 로 지우는 것과 가른다(04-1 `_keep` 과 같은 방식).
const Object _keep = Object();

/// 15-6 의 상태. 닉네임 · 키의 서버 값(saved)과 지금 입력을 같이 들고 "바뀐 칸" 을 가린다.
class BasicInfoEditUiState {
  const BasicInfoEditUiState({
    required this.savedNickname,
    required this.savedHeight,
    required this.nicknameInput,
    required this.heightInput,
    this.savedMbti,
    this.mbtiPoles = const {},
    this.isMbtiUnknown = false,
    this.savedReligion,
    this.religion,
    this.savedIsSmoker,
    this.isSmoker,
    this.savedAnimalType,
    this.animalType,
    this.savedImpressionType,
    this.impressionType,
    this.birthYear,
    this.gender,
    this.major,
    this.nicknameChangeableAt,
    this.nicknameCheck = NicknameCheck.none,
    this.nicknameRejection,
    this.heightRejection,
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  /// 열 때 서버 값. 키가 없으면 빈 글자.
  final String savedNickname;
  final String savedHeight;
  final String nicknameInput;
  final String heightInput;

  /// MBTI · 종교 · 흡연 · 얼굴상 · 인상의 서버 값(saved)과 지금 고른 값. 서버 값이 null 이면 아직 안 고른 것이다
  /// (MBTI 만 null 이 "선택 안 함" 이라 "모름" 으로 연다).
  final String? savedMbti;

  /// 축마다 고른 극. 네 축이 다 차면 글자가 된다([mbtiCode]).
  final Set<String> mbtiPoles;
  final bool isMbtiUnknown;
  final Religion? savedReligion;
  final Religion? religion;
  final bool? savedIsSmoker;
  final bool? isSmoker;
  final AnimalType? savedAnimalType;
  final AnimalType? animalType;
  final ImpressionType? savedImpressionType;
  final ImpressionType? impressionType;

  /// "바꿀 수 없는 정보" 잠금 행 값 — 서버 값 그대로(성별은 `male` · `female`). 서버가 안 주면 null.
  final int? birthYear;
  final String? gender;
  final String? major;

  /// 닉네임 잠금이 풀리는 때. null = 지금 바꿀 수 있다 — 판정은 서버 시계로 한다(계획서 2-1).
  final DateTime? nicknameChangeableAt;

  /// 디바운스가 끝난 뒤의 형식 · 중복 확인 결과(04-1 과 같은 값).
  final NicknameCheck nicknameCheck;

  /// 저장 때 서버가 닉네임 · 키 탓으로 돌려준 문구. 그 칸을 고치면 지운다.
  final String? nicknameRejection;
  final String? heightRejection;
  final bool isSubmitting;

  /// 어느 칸 탓인지 모르는 저장 실패(네트워크 등).
  final String? errorMessage;
  final bool completed;

  bool get isNicknameLocked => nicknameChangeableAt != null;
  bool get isNicknameChanged => nicknameInput != savedNickname;
  bool get isHeightChanged => heightInput != savedHeight;

  /// "모름" 이 켜졌거나 네 축이 다 찼으면 값이 정해진 것이다. 그 사이(반쪽)는 못 보낸다.
  bool get _isMbtiDecided => isMbtiUnknown || MbtiPoles.isComplete(mbtiPoles);

  /// 보낼 MBTI 글자. null = "선택 안 함"(또는 아직 반쪽).
  String? get mbtiCode => isMbtiUnknown ? null : MbtiPoles.code(mbtiPoles);

  /// 반쪽이면 "바뀌었지만 아직 못 보낸다" 로 본다 — 저장 버튼이 꺼진다([canSave]).
  bool get isMbtiChanged => !_isMbtiDecided || mbtiCode != savedMbti;
  bool get isReligionChanged => religion != savedReligion;
  bool get isSmokerChanged => isSmoker != savedIsSmoker;

  /// 얼굴상 · 인상은 한 쌍이다 — 둘 중 하나라도 바뀌면 둘 다 보낸다(서버는 한쪽만 오면 422).
  bool get isAppearanceChanged => animalType != savedAnimalType || impressionType != savedImpressionType;

  /// 저장 중 "점수를 다시 계산하는 중이에요" 안내(pen `Z6N24`). 서버가 매칭 점수 재료(MBTI · 얼굴상 · 인상)가 바뀔 때만
  /// 벡터를 다시 만든다 — 종교 · 흡연 · 닉네임 · 키만이면 보이지 않는다.
  bool get showsRecalculationNote => isSubmitting && (isMbtiChanged || isAppearanceChanged);

  /// 15-6-2 helper(`V3sicJ`). **한국 시각의 월 · 일** — 운영 DB 는 `+00:00` 으로 주고, 한국 밤 9시 이후 바꾼 사람은 UTC
  /// 날짜가 하루 앞선다. `toLocal()` 은 기기 · CI 시간대를 따라가 테스트가 흔들린다(옛 A7).
  String? get nicknameUnlockText {
    final at = nicknameChangeableAt;
    if (at == null) {
      return null;
    }
    final korea = at.toUtc().add(const Duration(hours: 9));
    return '${korea.month}월 ${korea.day}일부터 바꿀 수 있어요';
  }

  /// 04-1 과 같은 범위(서버 DB check 120~230).
  int? get heightCm {
    final value = int.tryParse(heightInput);
    return (value != null && value >= 120 && value <= 230) ? value : null;
  }

  /// 칸 아래 빨간 한 줄. 서버가 돌려준 문구가 먼저, 다음은 04-1 과 같은 형식 · 중복 문구.
  String? get nicknameError =>
      nicknameRejection ??
      switch (nicknameCheck) {
        NicknameCheck.invalid => '한글 또는 영문 2~5자로 입력해 주세요',
        NicknameCheck.taken => '이미 있는 닉네임이에요',
        _ => null,
      };

  String? get nicknameSuccess => nicknameCheck == NicknameCheck.available ? '사용할 수 있는 닉네임이에요' : null;
  String? get nicknameChecking => nicknameCheck == NicknameCheck.checking ? '확인 중…' : null;

  /// 04-1 과 같다 — 3자리를 다 친 뒤에도 범위 밖일 때만. 치는 도중에 띄우면 한 자 칠 때마다 깜빡인다.
  String? get heightError =>
      heightRejection ?? (heightInput.length == 3 && heightCm == null ? '숫자 3자리를 확인해 주세요' : null);

  /// 바뀌지 않은 칸은 보내지 않으니 검사하지 않는다. 중복 확인이 실패했거나 아직이어도 막지 않는다(04-1 과 같다).
  bool get _isNicknameReady =>
      !isNicknameChanged ||
      (BasicInfoUiState.nicknamePattern.hasMatch(nicknameInput) &&
          nicknameCheck != NicknameCheck.taken &&
          nicknameRejection == null);

  bool get _isHeightReady => !isHeightChanged || (heightCm != null && heightRejection == null);

  /// 바뀐 칸이 있어야 하고, 그 칸이 보낼 수 있는 값이어야 한다 — MBTI 는 반쪽이 아니고, 얼굴상 · 인상은 쌍이 다 찼다.
  bool get _isMbtiReady => !isMbtiChanged || _isMbtiDecided;
  bool get _isAppearanceReady => !isAppearanceChanged || (animalType != null && impressionType != null);

  bool get _hasChange =>
      isNicknameChanged || isHeightChanged || isMbtiChanged || isReligionChanged || isSmokerChanged || isAppearanceChanged;

  /// 바뀐 것이 없거나 형식 오류면 꺼진다(B2).
  bool get canSave =>
      !isSubmitting &&
      _hasChange &&
      _isNicknameReady &&
      _isHeightReady &&
      _isMbtiReady &&
      _isAppearanceReady;

  BasicInfoEditUiState copyWith({
    String? nicknameInput,
    String? heightInput,
    Set<String>? mbtiPoles,
    bool? isMbtiUnknown,
    Religion? religion,
    bool? isSmoker,
    AnimalType? animalType,
    ImpressionType? impressionType,
    NicknameCheck? nicknameCheck,
    Object? nicknameRejection = _keep,
    Object? heightRejection = _keep,
    bool? isSubmitting,
    Object? errorMessage = _keep,
    bool? completed,
  }) {
    return BasicInfoEditUiState(
      savedNickname: savedNickname,
      savedHeight: savedHeight,
      savedMbti: savedMbti,
      savedReligion: savedReligion,
      savedIsSmoker: savedIsSmoker,
      savedAnimalType: savedAnimalType,
      savedImpressionType: savedImpressionType,
      birthYear: birthYear,
      gender: gender,
      major: major,
      nicknameChangeableAt: nicknameChangeableAt,
      nicknameInput: nicknameInput ?? this.nicknameInput,
      heightInput: heightInput ?? this.heightInput,
      mbtiPoles: mbtiPoles ?? this.mbtiPoles,
      isMbtiUnknown: isMbtiUnknown ?? this.isMbtiUnknown,
      religion: religion ?? this.religion,
      isSmoker: isSmoker ?? this.isSmoker,
      animalType: animalType ?? this.animalType,
      impressionType: impressionType ?? this.impressionType,
      nicknameCheck: nicknameCheck ?? this.nicknameCheck,
      nicknameRejection: identical(nicknameRejection, _keep) ? this.nicknameRejection : nicknameRejection as String?,
      heightRejection: identical(heightRejection, _keep) ? this.heightRejection : heightRejection as String?,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: identical(errorMessage, _keep) ? this.errorMessage : errorMessage as String?,
      completed: completed ?? this.completed,
    );
  }
}
