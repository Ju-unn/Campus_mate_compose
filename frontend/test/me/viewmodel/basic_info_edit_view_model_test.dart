import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository_provider.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/viewmodel/basic_info_edit_view_model.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/model/basic_info_repository_provider.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:campus_mate/profile/viewmodel/basic_info_ui_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../profile/model/fake_basic_info_repository.dart';
import '../model/fake_me_repository.dart';

/// 서버 `errors.py` 의 문구 — 앱은 상태코드를 못 보고 문구만 받는다.
const _nicknameTaken = '이미 있는 닉네임이에요';
const _nicknameTooSoon = '닉네임은 30일에 한 번 바꿀 수 있어요';
const _invalidInput = '입력한 값을 다시 확인해 주세요';

/// 이름·학교는 지어낸 값이다.
MyProfile _profile({
  String nickname = '늑대',
  int? heightCm = 178,
  DateTime? nicknameChangeableAt,
  String? mbti,
  Religion? religion = Religion.none,
  bool? isSmoker = false,
  AnimalType? animalType = AnimalType.dog,
  ImpressionType? impressionType = ImpressionType.arab,
}) =>
    MyProfile(
      nickname: nickname,
      age: 24,
      university: '가나대학교',
      major: '경영학과',
      heightCm: heightCm,
      mbti: mbti,
      religion: religion,
      isSmoker: isSmoker,
      animalType: animalType,
      impressionType: impressionType,
      birthYear: 2001,
      gender: 'male',
      avatarUrl: null,
      preferredAgeMin: null,
      preferredAgeMax: null,
      preferredHeightMin: null,
      preferredHeightMax: null,
      bio: null,
      nicknameChangeableAt: nicknameChangeableAt,
    );

/// 15-6 기본 정보 수정(계획서 2026-09-28-me-profile.md A16 · 옛 A7 · B2 · B5).
void main() {
  late FakeMeRepository me;
  late FakeBasicInfoRepository nicknames;
  late ProviderContainer container;
  late ProviderSubscription<BasicInfoEditUiState> subscription;

  BasicInfoEditViewModel viewModel() => container.read(basicInfoEditViewModelProvider.notifier);
  BasicInfoEditUiState state() => subscription.read();

  /// 15-6 은 15-5 를 거쳐 열린다 — 그때는 내 프로필이 이미 읽혀 있다.
  Future<void> open(MyProfile profile) async {
    me = FakeMeRepository(Success(profile));
    nicknames = FakeBasicInfoRepository();
    container = ProviderContainer(
      overrides: [
        meRepositoryProvider.overrideWithValue(me),
        basicInfoRepositoryProvider.overrideWithValue(nicknames),
      ],
    );
    addTearDown(container.dispose);
    await container.read(myProfileProvider.future);
    subscription = container.listen(basicInfoEditViewModelProvider, (_, _) {});
  }

  group('열 때', () {
    test('서버 닉네임 · 키로 채워지고, 바뀐 것이 없어 저장이 꺼져 있다(B2)', () async {
      await open(_profile());

      expect(state().nicknameInput, '늑대');
      expect(state().heightInput, '178');
      expect(state().isNicknameLocked, isFalse);
      expect(state().canSave, isFalse);
    });

    test('키가 비어 있으면(서버 null) 키 칸도 빈 글자로 채워진다', () async {
      await open(_profile(heightCm: null));

      expect(state().heightInput, '');
      expect(state().canSave, isFalse);
    });

    test('잠금 중이면 닉네임이 잠기고 풀리는 날을 한국 시각으로 센다 — 2026-10-26T15:00Z 는 10월 27일', () async {
      await open(_profile(nicknameChangeableAt: DateTime.parse('2026-10-26T15:00:00+00:00')));

      expect(state().isNicknameLocked, isTrue);
      expect(state().nicknameUnlockText, '10월 27일부터 바꿀 수 있어요');
    });

    test('풀리는 날은 기기 시간대로 바꿔 받아도(toLocal) 한국 날짜 그대로다', () async {
      await open(_profile(nicknameChangeableAt: DateTime.parse('2026-10-26T15:00:00+00:00').toLocal()));

      expect(state().nicknameUnlockText, '10월 27일부터 바꿀 수 있어요');
    });

    test('잠겨 있지 않으면 풀리는 날 문구가 없다', () async {
      await open(_profile());

      expect(state().nicknameUnlockText, isNull);
    });
  });

  group('닉네임', () {
    testWidgets('다른 닉네임을 치면 300ms 뒤 중복을 묻는다(04-1 과 같은 시점)', (tester) async {
      await open(_profile());

      viewModel().changeNickname('호랑이');
      await tester.pump(const Duration(milliseconds: 290));
      expect(nicknames.checkedNicknames, isEmpty);
      await tester.pump(const Duration(milliseconds: 20));

      expect(nicknames.checkedNicknames, ['호랑이']);
      expect(state().nicknameSuccess, '사용할 수 있는 닉네임이에요');
      expect(state().canSave, isTrue);
    });

    testWidgets('지금 닉네임과 같으면 중복을 묻지 않는다', (tester) async {
      await open(_profile());

      viewModel().changeNickname('늑대왕');
      viewModel().changeNickname('늑대');
      await tester.pump(const Duration(milliseconds: 350));

      expect(nicknames.checkedNicknames, isEmpty);
      expect(state().nicknameError, isNull);
      expect(state().nicknameSuccess, isNull);
      expect(state().canSave, isFalse, reason: '되돌렸으니 바뀐 것이 없다(B2)');
    });

    testWidgets('중복이면 칸 아래 오류이고 저장이 꺼진다', (tester) async {
      await open(_profile());
      nicknames.nextAvailabilityResult = const Success(false);

      viewModel().changeNickname('호랑이');
      await tester.pump(const Duration(milliseconds: 350));

      expect(state().nicknameError, _nicknameTaken);
      expect(state().canSave, isFalse);
    });

    testWidgets('형식이 틀리면 서버에 묻지 않고 오류이고 저장이 꺼진다', (tester) async {
      await open(_profile());

      viewModel().changeNickname('ㄱㄴ');
      await tester.pump(const Duration(milliseconds: 350));

      expect(nicknames.checkedNicknames, isEmpty);
      expect(state().nicknameError, '한글 또는 영문 2~5자로 입력해 주세요');
      expect(state().canSave, isFalse);
    });

    testWidgets('확인 중이면 "확인 중…" 이 뜬다 — 막지는 않는다(04-1 과 같다)', (tester) async {
      await open(_profile());
      nicknames.availabilityGate = Completer<void>();

      viewModel().changeNickname('호랑이');
      await tester.pump(const Duration(milliseconds: 350));

      expect(state().nicknameChecking, '확인 중…');
      expect(state().canSave, isTrue);
      nicknames.availabilityGate!.complete();
      await tester.pump();
    });

    testWidgets('형식 · 중복 · 확인 중 · 사용 가능 문구는 04-1 과 한 글자도 다르지 않다', (tester) async {
      await open(_profile());
      String? onboarding(NicknameCheck check) => switch (check) {
            NicknameCheck.available => BasicInfoUiState(thisYear: 2026, nicknameCheck: check).nicknameSuccess,
            NicknameCheck.checking => BasicInfoUiState(thisYear: 2026, nicknameCheck: check).nicknameChecking,
            _ => BasicInfoUiState(thisYear: 2026, nicknameCheck: check).nicknameError,
          };

      viewModel().changeNickname('ㄱㄴ');
      await tester.pump(const Duration(milliseconds: 350));
      expect(state().nicknameError, onboarding(NicknameCheck.invalid));
      nicknames.nextAvailabilityResult = const Success(false);
      viewModel().changeNickname('호랑이');
      await tester.pump(const Duration(milliseconds: 350));
      expect(state().nicknameError, onboarding(NicknameCheck.taken));
      nicknames.nextAvailabilityResult = const Success(true);
      viewModel().changeNickname('사자');
      await tester.pump(const Duration(milliseconds: 350));
      expect(state().nicknameSuccess, onboarding(NicknameCheck.available));
    });
  });

  group('키', () {
    test('3자리를 다 친 뒤 범위(120~230) 밖일 때만 오류 — 04-1 과 같은 규칙', () async {
      await open(_profile());

      viewModel().changeHeight('17');
      expect(state().heightError, isNull);
      expect(state().canSave, isFalse, reason: '2자리는 아직 키가 아니다');

      viewModel().changeHeight('999');
      expect(state().heightError, '숫자 3자리를 확인해 주세요');
      expect(state().canSave, isFalse);

      viewModel().changeHeight('180');
      expect(state().heightError, isNull);
      expect(state().canSave, isTrue);
    });

    test('서버 값으로 되돌리면 다시 저장이 꺼진다(B2)', () async {
      await open(_profile());

      viewModel().changeHeight('180');
      viewModel().changeHeight('178');

      expect(state().canSave, isFalse);
    });
  });

  group('저장 — 바뀐 칸만 보낸다', () {
    test('키만 고치면 본문은 {"height_cm"} 뿐이고, 성공하면 끝나고 내 프로필을 다시 읽는다', () async {
      await open(_profile());
      viewModel().changeHeight('180');

      await viewModel().save();
      await container.read(myProfileProvider.future);

      expect(me.updates, [
        {'height_cm': 180},
      ]);
      expect(state().completed, isTrue);
      expect(me.calls, 2, reason: '저장 뒤 invalidate 로 GET /me/profile 을 한 번 더 부른다');
    });

    testWidgets('닉네임만 고치면 본문은 {"nickname"} 뿐이다', (tester) async {
      await open(_profile());
      viewModel().changeNickname('호랑이');
      await tester.pump(const Duration(milliseconds: 350));

      await viewModel().save();

      expect(me.updates, [
        {'nickname': '호랑이'},
      ]);
    });

    testWidgets('둘 다 고치면 둘 다 보낸다', (tester) async {
      await open(_profile());
      viewModel().changeNickname('호랑이');
      viewModel().changeHeight('180');
      await tester.pump(const Duration(milliseconds: 350));

      await viewModel().save();

      expect(me.updates, [
        {'nickname': '호랑이', 'height_cm': 180},
      ]);
    });

    test('잠금 중에도 키는 고쳐 저장할 수 있고, 닉네임은 보내지 않는다', () async {
      await open(_profile(nicknameChangeableAt: DateTime.parse('2026-10-26T15:00:00+00:00')));

      viewModel().changeHeight('180');
      expect(state().canSave, isTrue);
      await viewModel().save();

      expect(me.updates, [
        {'height_cm': 180},
      ]);
    });

    test('바뀐 것이 없으면 저장을 불러도 보내지 않는다', () async {
      await open(_profile());

      await viewModel().save();

      expect(me.updates, isEmpty);
    });

    test('저장하는 동안은 isSubmitting 이고 다시 누를 수 없다', () async {
      await open(_profile());
      viewModel().changeHeight('180');
      me.holdUpdate = Completer<void>();

      final saving = viewModel().save();

      expect(state().isSubmitting, isTrue);
      expect(state().canSave, isFalse);
      await viewModel().save();
      expect(me.updates, hasLength(1));
      me.holdUpdate!.complete();
      await saving;
      expect(state().isSubmitting, isFalse);
    });

    test('저장 중에 화면을 떠나도(autoDispose) 끝난 저장이 오류를 내지 않고 내 프로필은 다시 읽힌다', () async {
      await open(_profile());
      viewModel().changeHeight('180');
      me.holdUpdate = Completer<void>();
      final saving = viewModel().save();

      subscription.close();
      await Future<void>.delayed(Duration.zero);
      me.holdUpdate!.complete();
      await saving;
      await container.read(myProfileProvider.future);

      expect(me.updates, hasLength(1));
      expect(me.calls, 2);
    });

    test('basic_info_edit_is_filled_from_the_server_each_time_it_opens — 고치다 만 값은 닫으면 사라진다', () async {
      await open(_profile());
      viewModel().changeHeight('180');

      subscription.close();
      await Future<void>.delayed(Duration.zero);
      subscription = container.listen(basicInfoEditViewModelProvider, (_, _) {});

      expect(state().heightInput, '178');
      expect(state().canSave, isFalse);
    });
  });

  group('저장 실패 — 오류 자리(B5)', () {
    for (final message in [_nicknameTaken, _nicknameTooSoon]) {
      testWidgets('서버 409 "$message" 는 닉네임 칸 아래 — 저장이 꺼지고, 닉네임을 고치면 지운다', (tester) async {
        await open(_profile());
        viewModel().changeNickname('호랑이');
        await tester.pump(const Duration(milliseconds: 350));
        me.updateResult = FailureResult(ServerRejectedFailure(message));

        await viewModel().save();

        expect(state().nicknameError, message);
        expect(state().errorMessage, isNull);
        expect(state().completed, isFalse);
        expect(state().canSave, isFalse);
        expect(me.calls, 1, reason: '실패하면 다시 읽지 않는다');

        viewModel().changeNickname('사자');
        expect(state().nicknameError, isNull);
        await tester.pump(const Duration(milliseconds: 350)); // 디바운스를 끝내 둔다
      });
    }

    test('키를 보냈는데 서버 422 "입력한 값을 다시 확인해 주세요" 면 키 칸 아래 — 키를 고치면 지운다', () async {
      await open(_profile());
      viewModel().changeHeight('180');
      me.updateResult = const FailureResult(ServerRejectedFailure(_invalidInput));

      await viewModel().save();

      expect(state().heightError, _invalidInput);
      expect(state().nicknameError, isNull);
      expect(state().errorMessage, isNull);
      expect(state().canSave, isFalse);

      viewModel().changeHeight('181');
      expect(state().heightError, isNull);
      expect(state().canSave, isTrue);
    });

    test('그 밖의 실패(네트워크)는 칸이 아니라 저장 실패 문구 — 다시 누를 수 있다', () async {
      await open(_profile());
      viewModel().changeHeight('180');
      me.updateResult = const FailureResult(NetworkFailure());

      await viewModel().save();

      // pen 15-6c `C3oV5u` 의 고정 문구 — 실패 종류와 상관없이 같다.
      expect(state().errorMessage, '저장하지 못했어요. 잠시 후 다시 시도해 주세요');
      expect(state().nicknameError, isNull);
      expect(state().heightError, isNull);
      expect(state().completed, isFalse);
      expect(state().canSave, isTrue);
    });

    test('다시 저장하면 앞 실패 문구를 지운다', () async {
      await open(_profile());
      viewModel().changeHeight('180');
      me.updateResult = const FailureResult(NetworkFailure());
      await viewModel().save();
      me.updateResult = const Success(null);
      me.holdUpdate = Completer<void>();

      final saving = viewModel().save();

      expect(state().errorMessage, isNull);
      me.holdUpdate!.complete();
      await saving;
    });
  });

  group('MBTI · 종교 · 흡연 · 내 동물상 · 내 인상(15-6 확대)', () {
    test('열 때 서버 값으로 채워지고 바뀐 것이 없어 저장이 꺼져 있다', () async {
      await open(
        _profile(
          mbti: 'ENFP',
          religion: Religion.buddhist,
          isSmoker: true,
          animalType: AnimalType.fox,
          impressionType: ImpressionType.chic,
        ),
      );

      expect(state().mbtiPoles, {'E', 'N', 'F', 'P'});
      expect(state().isMbtiUnknown, isFalse);
      expect(state().religion, Religion.buddhist);
      expect(state().isSmoker, isTrue);
      expect(state().animalType, AnimalType.fox);
      expect(state().impressionType, ImpressionType.chic);
      expect(state().canSave, isFalse);
    });

    test('서버 MBTI 가 null(선택 안 함)이면 "모름" 이 켜진 채 열린다', () async {
      await open(_profile(mbti: null));

      expect(state().isMbtiUnknown, isTrue);
      expect(state().mbtiPoles, isEmpty);
      expect(state().canSave, isFalse);
    });

    test('잠금 행 값(출생연도 · 성별 · 학과)을 서버 값 그대로 들고 있다', () async {
      await open(_profile());

      expect((state().birthYear, state().gender, state().major), (2001, 'male', '경영학과'));
    });

    group('MBTI', () {
      test('같은 축의 다른 극을 누르면 바뀌고 저장이 켜진다 — 바뀐 MBTI 글자만 보낸다', () async {
        await open(_profile(mbti: 'ENFP'));

        viewModel().toggleMbtiPole('I');

        expect(state().mbtiPoles, {'I', 'N', 'F', 'P'});
        expect(state().canSave, isTrue);
        await viewModel().save();
        expect(me.updates, [
          {'mbti': 'INFP'},
        ]);
      });

      test('"모름" 을 누르면 MBTI 를 지운다 — 본문에 mbti: null', () async {
        await open(_profile(mbti: 'ENFP'));

        viewModel().toggleMbtiUnknown();

        expect(state().isMbtiUnknown, isTrue);
        expect(state().mbtiPoles, isEmpty);
        expect(state().canSave, isTrue);
        await viewModel().save();
        expect(me.updates, [
          {'mbti': null},
        ]);
      });

      test('선택 안 함이던 사람이 네 축을 다 고르면 글자를 보낸다', () async {
        await open(_profile(mbti: null));

        for (final pole in ['E', 'N', 'F', 'P']) {
          viewModel().toggleMbtiPole(pole);
        }

        expect(state().isMbtiUnknown, isFalse);
        expect(state().canSave, isTrue);
        await viewModel().save();
        expect(me.updates, [
          {'mbti': 'ENFP'},
        ]);
      });

      test('네 축이 다 차기 전에는 저장이 꺼진다 — 반쪽 MBTI 는 못 보낸다', () async {
        await open(_profile(mbti: null));

        viewModel().toggleMbtiPole('E');
        viewModel().toggleMbtiPole('N');

        expect(state().canSave, isFalse);
      });

      test('같은 값으로 되돌리면 다시 꺼진다(칸별 변경 감지)', () async {
        await open(_profile(mbti: 'ENFP'));

        viewModel().toggleMbtiPole('I');
        viewModel().toggleMbtiPole('E');

        expect(state().canSave, isFalse);
      });

      test('모름을 눌렀다가 다시 누르면 빈 선택이다(반쪽) — 저장은 꺼진다', () async {
        await open(_profile(mbti: 'ENFP'));

        viewModel().toggleMbtiUnknown();
        viewModel().toggleMbtiUnknown();

        expect(state().isMbtiUnknown, isFalse);
        expect(state().mbtiPoles, isEmpty);
        expect(state().canSave, isFalse);
      });
    });

    group('종교 · 흡연', () {
      test('종교만 바꾸면 종교만 보낸다', () async {
        await open(_profile());

        viewModel().changeReligion(Religion.catholic);
        await viewModel().save();

        expect(me.updates, [
          {'religion': 'catholic'},
        ]);
      });

      test('흡연을 "한다" 로 바꾸면 is_smoker: true 만 보낸다 — 원래 값으로 돌리면 꺼진다', () async {
        await open(_profile(isSmoker: false));

        viewModel().changeIsSmoker(true);
        expect(state().canSave, isTrue);
        viewModel().changeIsSmoker(false);
        expect(state().canSave, isFalse);
        viewModel().changeIsSmoker(true);
        await viewModel().save();

        expect(me.updates, [
          {'is_smoker': true},
        ]);
      });
    });

    group('내 동물상 · 내 인상(쌍)', () {
      test('동물상만 바꿔도 동물상과 인상 둘 다 보낸다', () async {
        await open(_profile(animalType: AnimalType.dog, impressionType: ImpressionType.arab));

        viewModel().changeAnimalType(AnimalType.wolf);
        await viewModel().save();

        expect(me.updates, [
          {'animal_type': 'wolf', 'impression_type': 'arab'},
        ]);
      });

      test('인상만 바꿔도 둘 다 보낸다', () async {
        await open(_profile(animalType: AnimalType.dog, impressionType: ImpressionType.arab));

        viewModel().changeImpressionType(ImpressionType.innocent);
        await viewModel().save();

        expect(me.updates, [
          {'animal_type': 'dog', 'impression_type': 'innocent'},
        ]);
      });

      test('둘 다 원래대로 돌리면 꺼진다', () async {
        await open(_profile(animalType: AnimalType.dog, impressionType: ImpressionType.arab));

        viewModel().changeAnimalType(AnimalType.cat);
        viewModel().changeAnimalType(AnimalType.dog);

        expect(state().canSave, isFalse);
      });

      test('서버 값이 둘 다 없던 사람이 한쪽만 고르면 꺼져 있다 — 쌍이 다 차야 보낸다', () async {
        await open(_profile(animalType: null, impressionType: null));

        viewModel().changeAnimalType(AnimalType.cat);
        expect(state().canSave, isFalse);
        viewModel().changeImpressionType(ImpressionType.kind);
        expect(state().canSave, isTrue);
      });
    });

    test('여러 칸을 같이 바꾸면 바뀐 칸만 한 번에 보낸다 — 키 · MBTI · 종교', () async {
      await open(_profile(mbti: 'ENFP'));
      viewModel().changeHeight('181');
      viewModel().toggleMbtiPole('I');
      viewModel().changeReligion(Religion.protestant);

      await viewModel().save();

      expect(me.updates, [
        {'height_cm': 181, 'mbti': 'INFP', 'religion': 'protestant'},
      ]);
      expect(state().completed, isTrue);
    });

    group('"점수를 다시 계산하는 중이에요" 안내(저장 중에만)', () {
      Future<void> saveHolding() async {
        me.holdUpdate = Completer<void>();
        unawaited(viewModel().save());
        await Future<void>.delayed(Duration.zero);
      }

      for (final (name, change) in <(String, void Function(BasicInfoEditViewModel))>[
        ('MBTI', (vm) => vm.toggleMbtiPole('I')),
        ('내 동물상', (vm) => vm.changeAnimalType(AnimalType.cat)),
        ('내 인상', (vm) => vm.changeImpressionType(ImpressionType.tofu)),
      ]) {
        test('$name 이 바뀐 채 저장 중이면 보인다', () async {
          await open(_profile(mbti: 'ENFP'));
          change(viewModel());
          expect(state().showsRecalculationNote, isFalse, reason: '저장 전에는 안 보인다');

          await saveHolding();

          expect(state().isSubmitting, isTrue);
          expect(state().showsRecalculationNote, isTrue);
          me.holdUpdate!.complete();
          await Future<void>.delayed(Duration.zero);
        });
      }

      for (final (name, change) in <(String, void Function(BasicInfoEditViewModel))>[
        ('종교', (vm) => vm.changeReligion(Religion.catholic)),
        ('흡연', (vm) => vm.changeIsSmoker(true)),
        ('키', (vm) => vm.changeHeight('181')),
      ]) {
        test('$name 만 바뀐 채 저장 중이면 숨긴다 — 점수가 다시 계산되지 않는다', () async {
          await open(_profile(mbti: 'ENFP'));
          change(viewModel());

          await saveHolding();

          expect(state().isSubmitting, isTrue);
          expect(state().showsRecalculationNote, isFalse);
          me.holdUpdate!.complete();
          await Future<void>.delayed(Duration.zero);
        });
      }

      testWidgets('닉네임만 바뀐 채 저장 중이면 숨긴다', (tester) async {
        await open(_profile(mbti: 'ENFP'));
        viewModel().changeNickname('호랑이');
        await tester.pump(const Duration(milliseconds: 350));

        me.holdUpdate = Completer<void>();
        unawaited(viewModel().save());
        await tester.pump();

        expect(state().isSubmitting, isTrue);
        expect(state().showsRecalculationNote, isFalse);
        me.holdUpdate!.complete();
        await tester.pump();
      });
    });

    test('저장에 성공하면 completed 가 켜지고 내 프로필을 다시 읽는다', () async {
      await open(_profile(mbti: 'ENFP'));
      viewModel().toggleMbtiPole('I');

      await viewModel().save();
      await container.read(myProfileProvider.future);

      expect(state().completed, isTrue);
      expect(me.calls, 2);
    });

    test('서버가 422 로 거절해도(키를 안 보냈으면) 칸 탓이 아니라 pen 저장 실패 문구다', () async {
      await open(_profile(mbti: 'ENFP'));
      viewModel().toggleMbtiPole('I');
      me.updateResult = const FailureResult(ServerRejectedFailure(_invalidInput));

      await viewModel().save();

      expect(state().errorMessage, '저장하지 못했어요. 잠시 후 다시 시도해 주세요');
      expect(state().heightError, isNull);
      expect(state().completed, isFalse);
      expect(state().canSave, isTrue);
    });

    test('저장 중에는 이 칸들도 바꿀 수 없다', () async {
      await open(_profile(mbti: 'ENFP'));
      viewModel().toggleMbtiPole('I');
      me.holdUpdate = Completer<void>();
      final saving = viewModel().save();
      await Future<void>.delayed(Duration.zero);

      viewModel().toggleMbtiPole('E');
      viewModel().changeReligion(Religion.catholic);
      viewModel().changeIsSmoker(true);
      viewModel().changeAnimalType(AnimalType.cat);

      expect(state().mbtiPoles, {'I', 'N', 'F', 'P'});
      expect(state().religion, Religion.none);
      expect(state().isSmoker, isFalse);
      expect(state().animalType, AnimalType.dog);
      me.holdUpdate!.complete();
      await saving;
    });
  });
}
