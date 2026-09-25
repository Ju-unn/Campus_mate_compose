import 'package:campus_mate/common/phone_number_formatter.dart';

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
    this.gender,
    this.mbtiPoles = const {},
    this.isMbtiUnknown = false,
    this.isSubmitting = false,
    this.errorMessage,
    this.completed = false,
  });

  /// 화면이 뜬 해. 나이 하한을 여기서 센다 — 테스트가 고정할 수 있게 밖에서 받는다.
  final int thisYear;

  /// 서버와 **같은 기준**이어야 한다(`backend/app/profile_onboarding/schemas.py` `MIN_AGE`).
  /// 어긋나면 "다음"은 켜지는데 서버가 422 를 돌려줘 04-1 에 갇힌다.
  static const int minAge = 19;

  final String nicknameInput;

  /// 디바운스가 끝난 뒤의 형식·중복 확인 결과. 문구는 [nicknameError]·[nicknameSuccess] 가 만든다.
  final NicknameCheck nicknameCheck;
  final String birthYearInput;
  final String heightInput;
  final String phoneNumberInput;
  final String? gender;
  /// 축마다 고른 극(E/I · N/S · T/F · J/P). 네 축을 다 골라야 서버로 보낼 값이 된다.
  final Set<String> mbtiPoles;

  /// "모름" 을 고른 상태. 값은 보내지 않는다(MBTI 는 선택 항목이다).
  final bool isMbtiUnknown;

  static const List<List<String>> mbtiAxes = [
    ['E', 'I'],
    ['N', 'S'],
    ['T', 'F'],
    ['J', 'P'],
  ];

  /// 네 축을 모두 고른 경우에만 채워진다.
  String? get mbti {
    final letters = [
      for (final axis in mbtiAxes) axis.firstWhere(mbtiPoles.contains, orElse: () => ''),
    ];
    return letters.contains('') ? null : letters.join();
  }
  final bool isSubmitting;
  final String? errorMessage;
  final bool completed;

  /// 범위 밖이면 오류 문구 없이 "다음"만 꺼진다(pen 04-1 — 출생연도에는 오류 자리가 없다).
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

  /// 오류색으로 입력칸 바로 아래 한 줄(DESIGN §8.5).
  String? get nicknameError => switch (nicknameCheck) {
    NicknameCheck.invalid => '한글 또는 영문 2~5자로 입력해 주세요',
    NicknameCheck.taken => '이미 있는 닉네임이에요',
    _ => null,
  };

  /// 같은 자리에 성공색으로 한 줄. 오류가 있으면 그쪽이 먼저다.
  String? get nicknameSuccess =>
      nicknameCheck == NicknameCheck.available ? '사용할 수 있는 닉네임이에요' : null;

  /// 서버 답을 기다리는 잠깐 동안 같은 자리에 회색으로 한 줄.
  String? get nicknameChecking => nicknameCheck == NicknameCheck.checking ? '확인 중…' : null;

  /// 키 칸은 평소엔 아무것도 안 보이고, **3자리를 다 친 뒤에도 범위 밖일 때만** 오류를 띄운다
  /// (pen 04-1 "도움말은 필요할 때만"). 치는 도중에 띄우면 한 자 칠 때마다 문구가 깜빡인다.
  String? get heightError =>
      heightInput.length == 3 && heightCm == null ? '숫자 3자리를 확인해 주세요' : null;

  /// 확인이 실패했거나(네트워크) 아직 안 끝났어도 막지 않는다 — 제출 때 서버가 다시 본다.
  bool get _isNicknameValid {
    return nicknamePattern.hasMatch(nicknameInput) && nicknameCheck != NicknameCheck.taken;
  }

  bool get canSubmit {
    return !isSubmitting &&
        _isNicknameValid &&
        birthYear != null &&
        heightCm != null &&
        // 반만 친 번호로 넘어가면 서버가 400 을 돌려주고 04-1 에 다시 갇힌다.
        phoneDigits.length == PhoneNumberFormatter.maxDigits &&
        gender != null;
  }
}
