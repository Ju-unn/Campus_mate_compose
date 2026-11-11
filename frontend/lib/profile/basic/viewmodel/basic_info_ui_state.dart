import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/phone_number_formatter.dart';
import 'package:campus_mate/me/model/data/my_profile.dart';
import 'package:campus_mate/profile/basic/model/data/mbti_poles.dart';
import 'package:campus_mate/profile/basic/model/data/signup_phone_number.dart';
import 'package:campus_mate/profile/basic/viewmodel/phone_verify_ui_state.dart';

/// 닉네임 한 줄 안내의 상태(DESIGN.md §8.5 `nickname-field` "인라인 중복확인 상태").
/// 입력이 바뀌면 [none] 으로 돌아가고, 디바운스가 끝난 뒤 형식·중복 확인 결과로 채워진다.
enum NicknameCheck { none, invalid, checking, available, taken }

/// 기본 정보 화면(DESIGN.md 화면 04-1)의 상태.
class BasicInfoUiState {
  const BasicInfoUiState({
    required this.thisYear,
    this.nicknameInput = '',
    this.nicknameCheck = NicknameCheck.none,
    this.birthYearInput = '',
    this.heightInput = '',
    this.phoneNumberInput = '',
    this.rejectedPhoneDigits,
    this.phoneVerify = const PhoneVerifyUiState(),
    this.gender,
    this.mbtiPoles = const {},
    this.isMbtiUnknown = false,
    this.isSubmitting = false,
    this.error,
    this.completed = false,
  });

  /// 화면이 뜬 해. 나이 하한을 여기서 센다 — 테스트가 고정할 수 있게 밖에서 받는다.
  final int thisYear;

  /// 서버와 **같은 기준**이어야 한다(`backend/app/profile_onboarding/schemas.py` `MIN_AGE`).
  /// 어긋나면 "다음"은 켜지는데 서버가 422 를 돌려줘 04-1 에 갇힌다.
  static const int minAge = 19;

  final String nicknameInput;

  /// 디바운스가 끝난 뒤의 형식·중복 확인 결과. 오류 종류는 [nicknameError] 가 고르고, 확인 중 · 사용 가능 글자는 view 가
  /// 이 값으로 고른다.
  final NicknameCheck nicknameCheck;
  final String birthYearInput;
  final String heightInput;
  final String phoneNumberInput;

  /// 서버가 422 `phone_number_invalid` 로 거절한 번호(숫자만). 앱 규칙을 지났어도 서버가 막은 번호라 같은 번호로는
  /// 다시 내지 않는다 — 번호를 고치면 저절로 걷힌다. 폰에 남기지 않는다([toDraft] 에 없다).
  final String? rejectedPhoneDigits;

  /// 휴대폰 문자 인증(pen 04-1 2c). 폰에 남기지 않는다([toDraft] 에 없다) — 다시 열면 번호부터 다시 인증한다.
  final PhoneVerifyUiState phoneVerify;
  final String? gender;
  /// 축마다 고른 극(E/I · N/S · T/F · J/P). 네 축을 다 골라야 서버로 보낼 값이 된다.
  final Set<String> mbtiPoles;

  /// "모름" 을 고른 상태. 값은 보내지 않는다(MBTI 는 선택 항목이다).
  final bool isMbtiUnknown;

  static const List<List<String>> mbtiAxes = MbtiPoles.axes;

  /// 네 축을 모두 고른 경우에만 채워진다.
  String? get mbti => MbtiPoles.code(mbtiPoles);
  final bool isSubmitting;
  final Failure? error;
  final bool completed;

  /// 범위 밖이면 "다음"이 꺼진다. 문구는 나이 미달일 때만 [birthYearError] 가 단다.
  int? get birthYear {
    final value = int.tryParse(birthYearInput);
    return (value != null && value >= 1950 && value <= thisYear - minAge) ? value : null;
  }

  /// 서버로는 하이픈 없이 숫자만 보낸다 — 저장 형식(E.164)은 서버가 정한다.
  String get phoneDigits => phoneNumberInput.replaceAll(RegExp(r'\D'), '');

  int? get heightCm {
    final value = int.tryParse(heightInput);
    return (value != null && value >= 120 && value <= 230) ? value : null;
  }

  /// 보낼 수 있는 닉네임의 형식. 입력 단계에서 자모(ㄱ·ㅏ)는 통과시키지만(한글 입력기가 조합 중에
  /// 자모를 먼저 넣는다) 보낼 값은 완성형이어야 한다 — 그 마지막 관문이 여기다.
  static final RegExp nicknamePattern = RegExp(r'^[가-힣a-zA-Z]{2,5}$');

  /// 오류색으로 입력칸 바로 아래 한 줄(DESIGN §8.5)의 종류. 글자는 view 가 `context.errorText` 로 만든다.
  /// 같은 자리의 성공색(사용 가능) · 회색(확인 중) 한 줄은 view 가 [nicknameCheck] 로 고른다 — 오류가 있으면 그쪽이 먼저다.
  Failure? get nicknameError => switch (nicknameCheck) {
    NicknameCheck.invalid => const AppErrorFailure(AppError.nicknameInvalid),
    NicknameCheck.taken => const AppErrorFailure(AppError.nicknameTaken),
    _ => null,
  };

  /// 키 칸은 평소엔 아무것도 안 보이고, **3자리를 다 친 뒤에도 범위 밖일 때만** 오류를 띄운다
  /// (pen 04-1 "도움말은 필요할 때만"). 치는 도중에 띄우면 한 자 칠 때마다 문구가 깜빡인다.
  /// 문구는 범위를 그대로 알려 준다(2026-11-02 앱 1.0.1, 종전 "숫자 3자리를 확인해 주세요").
  Failure? get heightError =>
      heightInput.length == 3 && heightCm == null ? const AppErrorFailure(AppError.heightRange) : null;

  /// 가입용 번호 규칙([SignupPhoneNumber])에 걸리면 **11자리를 다 친 뒤에만** 오류를 띄운다(키 칸과 같은 방식).
  /// 서버도 같은 규칙으로 다시 본다 — 앱은 바로 알려 주고 "다음"을 끈다.
  /// 서버가 거절한 번호([rejectedPhoneDigits])도 같은 자리 · 같은 문구다(서버 422 본문 `detail` 과 같은 글자).
  Failure? get phoneNumberError {
    final isFilled = phoneDigits.length == PhoneNumberFormatter.maxDigits;
    return isFilled && !_isPhoneAcceptable ? const AppErrorFailure(AppError.phoneInvalid) : null;
  }

  bool get _isPhoneAcceptable => SignupPhoneNumber.accepts(phoneDigits) && phoneDigits != rejectedPhoneDigits;

  /// 번호 줄 아래 상태 줄의 오류 — 서버가 막은 이유(⑦ ⑫ 잠시 후 · 010)가 먼저, 없으면 앱 규칙에 걸린 번호.
  Failure? get phoneStatusError => phoneVerify.error ?? phoneNumberError;

  /// 지금 칸의 번호가 인증된 번호인가(⑥). "다음" 은 이것이 참일 때만 켜진다(대장 결정 11-10).
  bool get isPhoneVerified =>
      phoneVerify.step == PhoneVerifyStep.verified && phoneVerify.verifiedDigits == phoneDigits;

  /// 인증번호 받기 · 다시 받기를 보낼 수 있는가. 받기 버튼(①②⑦)과 다시 받기 글자(③④⑤⑬)가 같이 쓴다.
  bool get canSendCode =>
      !isSubmitting &&
      _isPhoneAcceptable &&
      !phoneVerify.isSending &&
      !phoneVerify.isVerifying &&
      phoneVerify.step != PhoneVerifyStep.verified &&
      !phoneVerify.isDailyLimited &&
      phoneVerify.resendSecondsLeft == 0;

  /// 출생연도는 **나이가 모자랄 때만** 오류를 띄운다(사용자 결정 2026-09-29). 치는 도중(3자리 이하)은 값이 작아
  /// 걸리지 않는다. 문구는 서버 422(schemas.py)와 같다 — 해가 바뀌면 연도도 따라 바뀐다. 1950 이전은 꺼지기만 한다.
  Failure? get birthYearError {
    final value = int.tryParse(birthYearInput);
    return value != null && value > thisYear - minAge ? BirthYearFailure(thisYear - minAge) : null;
  }

  /// 폰에 임시 저장할 값. **전화번호는 넣지 않는다** — 평문으로 폰에 남기지 않는다(2026-10-08 사용자 결정).
  /// 앱을 다시 열면 전화번호 칸만 비어 있고 다시 입력받는다. 확인 결과 · 진행 표시도 남기지 않는다.
  Map<String, Object?> toDraft() => {
        'nickname': nicknameInput,
        'birthYear': birthYearInput,
        'height': heightInput,
        'gender': gender,
        'mbtiPoles': mbtiPoles.toList(),
        'mbtiUnknown': isMbtiUnknown,
      };

  /// [toDraft] 로 남긴 값으로 처음 상태를 만든다. 모양이 안 맞으면 던진다 — 저장소가 받아서 버린다.
  static BasicInfoUiState fromDraft(Map<String, Object?> data, {required int thisYear}) {
    return BasicInfoUiState(
      thisYear: thisYear,
      nicknameInput: data['nickname'] as String,
      birthYearInput: data['birthYear'] as String,
      heightInput: data['height'] as String,
      gender: data['gender'] as String?,
      mbtiPoles: _mbtiPolesFromDraft(data['mbtiPoles']),
      isMbtiUnknown: data['mbtiUnknown'] as bool,
    );
  }

  /// 뒤로가기로 돌아왔을 때 이미 저장한 값으로 처음 상태를 만든다. **전화번호는 비운다** — 서버가 암호문으로만 들고 있어
  /// 앱이 읽을 수 없다(사용자 결정 ④, 다시 입력). MBTI 가 없으면 "모름" 이다(15-6 편집과 같은 규칙).
  static BasicInfoUiState fromProfile(MyProfile profile, {required int thisYear}) {
    return BasicInfoUiState(
      thisYear: thisYear,
      nicknameInput: profile.nickname,
      birthYearInput: profile.birthYear?.toString() ?? '',
      heightInput: profile.heightCm?.toString() ?? '',
      gender: profile.gender,
      mbtiPoles: MbtiPoles.fromCode(profile.mbti),
      isMbtiUnknown: profile.mbti == null,
    );
  }

  /// 남긴 MBTI 극. 네 축의 글자(E/I · N/S · T/F · J/P)가 아니면 던진다.
  static Set<String> _mbtiPolesFromDraft(Object? raw) {
    final poles = (raw as List).cast<String>().toSet();
    if (!poles.every(mbtiAxes.expand((axis) => axis).contains)) {
      throw const FormatException('MBTI 극이 아닌 글자');
    }
    return poles;
  }

  /// 확인이 실패했거나(네트워크) 아직 안 끝났어도 막지 않는다 — 제출 때 서버가 다시 본다.
  bool get _isNicknameValid {
    return nicknamePattern.hasMatch(nicknameInput) && nicknameCheck != NicknameCheck.taken;
  }

  bool get canSubmit {
    return !isSubmitting &&
        _isNicknameValid &&
        birthYear != null &&
        heightCm != null &&
        // 반만 친 번호 · 가짜 모양 번호로 넘어가면 서버가 400 을 돌려주고 04-1 에 다시 갇힌다.
        _isPhoneAcceptable &&
        isPhoneVerified &&
        gender != null;
  }
}
