import 'dart:io';
import 'dart:math';

import 'package:campus_mate/auth/viewmodel/student_verification_view_model.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/app_checkbox.dart';
import 'package:campus_mate/common/widgets/labeled_field.dart';
import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/consent/view/consent_row.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/common/widgets/trait_slider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/home/viewmodel/home_summary_provider.dart';
import 'package:campus_mate/profile/view/avatar_generation_screen.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_view_model.dart';
import 'package:campus_mate/profile/viewmodel/ideal_conditions_view_model.dart';
import 'package:campus_mate/profile/viewmodel/photos_ui_state.dart';
import 'package:campus_mate/profile/viewmodel/photos_view_model.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support.dart';

part 'area1_b2.dart';
part 'area1_b3.dart';
part 'area1_b4.dart';
part 'area1_emu.dart';

/// 영역 1 묶음 1 폰 가설 36(37 중 E-ONB-05 는 두 기기라 묶음 4). PC 쪽은 e2e/area1.py 의 같은 번호 — 계정을 만들어
/// 1회용 토큰(`token_hash`)을 넘기고, 앱이 pass 를 말하면 DB 를 본다. 화면 글자는 시나리오가 아니라 지금 화면 코드에서 옮겼다.
/// 찾기는 Key 없이 화면 글자 · 입력칸 힌트 · 라벨 · 공용 위젯 종류로 한다.
typedef Area1Case = Future<Map<String, Object?>?> Function(WidgetTester tester, Map<String, dynamic> job);

/// 화면 이름 → 그 화면에만 있는 제목 글자.
const screens = {
  'login': '대학 이메일로 시작해요', // 2 sign_up_screen
  'code': '인증 코드를 입력해요', // 3 verify_code_screen
  'consent': '서비스 이용을 위해 동의해 주세요', // 02-c consent_screen
  '3b': '학교와 재학 상태를 확인해요', // student_verification_screen _Hero
  '3c': '학과와 학번을 알려주세요', // school_info_screen
  '04-1': '닉네임과 기본 정보를\n알려주세요', // basic_info_screen
  '04-1b': '카카오톡 아이디를 알려주세요', // kakao_id_screen
  '04-2': '실제 사진을 올려주세요', // photos_screen
  'suspended': '이용이 제한된 계정이에요', // account_suspended_screen
  // 묶음 2(area1_b2.dart)
  'consent-renew': '약관이 바뀌었어요', // 02-c-4 consent_screen
  '04-4': '어떤 얼굴상인가요?', // appearance_type_screen
  '04-5': '주로 관심 있는 게 뭐예요?', // tag_picker_kind interests
  '04-6': '어떤 특징을 가지고 계신가요?', // tag_picker_kind myTraits
  '05-01': '밖에 나가서 활동하는 걸\n좋아하시나요?', // survey_screen 첫 문항
  // 05-12 는 완성 행이 없으면 실패 화면이라 글자로 못 찾는다 — screen() 이 화면 종류로 찾는다.
  '05-12': '아바타 만들기', // avatar_generation_screen(완성)
  '06-1': '어떤 사람이 좋아요?', // ideal_conditions_screen
  '06-2': '어떤 분을 만나고 싶나요?', // tag_picker_kind idealTraits
  '06-2a': '이런 사람이 좋아요를\n자유롭게 적어주세요', // ideal_note_screen
  '06-2b': '설문을 읽고 있어요', // bio_draft_loading_screen
  '06-3': '이렇게 소개해볼까요?', // bio_screen
  '20': '친구에게 받은 코드가 있나요?', // referral_code_screen
  '20d': 'CampusMate를 어떻게 알게 되셨나요?', // acquisition_screen
  '06-4': '아는 사람을 만나고 싶지 않다면 연락처로 미리 막을 수 있어요', // onboarding_contact_block_screen("지인 차단" 은 두 번 나온다)
  'home': 'CampusMate', // screen() 이 글자 대신 HomeScreen 으로 찾는다 — 스플래시(하단 내비 없음)에도 같은 글자가 있다
  'settings': '설정', // settings_screen 앱바
  // 묶음 3(area1_b3.dart)
  '04-3': '아바타로 만들 사진을 골라주세요', // avatar_source_screen
  // B에뮬(area1_emu.dart)
  '01-1': '인터넷 연결을 확인해 주세요', // offline_screen
};

const _rejected = '허용되지 않은 학교 이메일이에요';
const _wrongCode = '코드가 맞지 않아요. 다시 확인해 주세요.';
const _nicknameOk = '사용할 수 있는 닉네임이에요';
const _nicknameBad = '한글 또는 영문 2~5자로 입력해 주세요';
const _nicknameTaken = '이미 있는 닉네임이에요';
const _heightBad = '숫자 3자리를 확인해 주세요';
const _consentCta = '동의하고 계속하기';

Finder screen(String name) => switch (name) {
      '05-12' => find.byType(AvatarGenerationScreen),
      'home' => find.byType(HomeScreen),
      _ => find.text(screens[name]!),
    };

/// 입력칸 — 힌트(placeholder) 또는 라벨 글자로.
Finder input(String hintOrLabel) => find.byWidgetPredicate(
      (w) => w is TextField && (w.decoration?.hintText == hintOrLabel || w.decoration?.labelText == hintOrLabel),
    );

/// 힌트 없는 [LabeledField](04-1 닉네임)의 입력칸.
Finder labeled(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is LabeledField && w.label == label),
      matching: find.byType(TextField),
    );

Finder button(String label) => find.widgetWithText(AppButton, label);

bool enabled(WidgetTester tester, String label) {
  final widget = tester.widget<AppButton>(button(label).last);
  return widget.onPressed != null && !widget.isLoading;
}

void must(bool ok, String problem) {
  if (!ok) throw TestFailure(problem);
}

/// 실제 시간으로 [duration] 동안 프레임을 흘린다.
Future<void> wait(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// [finder] 가 [within] 안에 나타나면 걸린 시간, 아니면 null.
Future<Duration?> appears(WidgetTester tester, Finder finder, Duration within) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < within) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return watch.elapsed;
  }
  return null;
}

Future<void> arrive(WidgetTester tester, String name, {Duration timeout = const Duration(seconds: 30)}) =>
    pumpUntil(tester, screen(name), timeout: timeout);

Future<void> tap(WidgetTester tester, Finder finder) async {
  must(finder.evaluate().isNotEmpty, '못 찾음: $finder'); // 없으면 "Bad state: No element" 만 남는다
  await tester.ensureVisible(finder.last);
  await tester.pump();
  await tester.tap(finder.last);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> type(WidgetTester tester, Finder field, String text) async {
  must(field.evaluate().isNotEmpty, '못 찾음: $field');
  await tester.ensureVisible(field.first);
  await tester.enterText(field.first, text);
  await tester.pump(const Duration(milliseconds: 300));
}

String fieldText(WidgetTester tester, Finder field) => tester.widget<TextField>(field.first).controller?.text ?? '';

/// 앞 가설의 세션을 지우고([fresh] 가 false 면 그대로 둔다) 일감의 토큰으로 로그인한 뒤 [body] 를 돈다.
Area1Case _session(Area1Case body) => (tester, job) async {
      if (job['fresh'] != false) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

bool _fresh(Map<String, dynamic> job) => job['fresh'] != false;

/// [expect] 화면에 닿는다. 다시 켠 경우(fresh=false)엔 5초(스플래시 2 + 3) 안, 로그인 화면이 한 번도 안 나와야 한다.
Future<Map<String, Object?>?> _arriveAt(WidgetTester tester, Map<String, dynamic> job) async {
  final name = job['expect'] as String;
  final limit = _fresh(job) ? const Duration(seconds: 30) : const Duration(seconds: 5);
  final watch = Stopwatch()..start();
  var sawLogin = false;
  var found = false;
  while (watch.elapsed < limit && !found) {
    await tester.pump(const Duration(milliseconds: 100));
    sawLogin |= name != 'login' && screen('login').evaluate().isNotEmpty;
    found = screen(name).evaluate().isNotEmpty;
  }
  must(found, '${limit.inSeconds}초 안에 $name 화면이 안 나옴');
  must(_fresh(job) || !sawLogin, '다시 켰는데 로그인 화면이 나옴');
  return {'note': '${watch.elapsedMilliseconds}ms'};
}

Future<void> _consentRow(WidgetTester tester, String label) => tap(tester, find.widgetWithText(ConsentRow, label));

int _checkedBoxes(WidgetTester tester) =>
    tester.widgetList<AppCheckbox>(find.byType(AppCheckbox)).where((box) => box.checked).length;

bool _allAgreeChecked(WidgetTester tester) => tester
    .widget<AppCheckbox>(find.descendant(of: find.widgetWithText(ConsentRow, '전체 동의'), matching: find.byType(AppCheckbox)))
    .checked;

/// 3b 갤러리 대신 앱에 든 마스코트 그림을 고르게 한다(제출은 안 한다).
Future<void> _fakeGallery(WidgetTester tester) async {
  final data = await rootBundle.load('assets/images/mascot-male.png');
  final file = File('${(await getTemporaryDirectory()).path}/e2e-mascot.png');
  await file.writeAsBytes(data.buffer.asUint8List());
  ProviderScope.containerOf(tester.element(screen('3b')))
      .read(studentVerificationViewModelProvider.notifier)
      .pickFromGallery = () async => file;
  await tap(tester, find.text('사진을 첨부해주세요'));
}

const _realNameHint = '학생증에 표기된 이름';
const _submitProof = '확인 요청하기';

/// 실명 [name] 을 넣으면 제출 버튼이 [on] 인지.
Future<void> _realName(WidgetTester tester, String name, {required bool on}) async {
  await type(tester, input(_realNameHint), name);
  must(enabled(tester, _submitProof) == on, '실명 "$name" 에 버튼이 ${on ? '꺼짐' : '켜짐'}');
}

final _random = Random();

String _englishNickname() => String.fromCharCodes(List.generate(5, (_) => 97 + _random.nextInt(26)));

String _koreanNickname() => String.fromCharCodes(List.generate(3, (_) => 0xAC00 + _random.nextInt(11172)));

Future<void> _nickname(WidgetTester tester, String nickname, String message) async {
  await type(tester, labeled('닉네임'), nickname);
  await pumpUntil(tester, find.text(message), timeout: const Duration(seconds: 5));
}

/// 04-1 을 다음이 켜지게 채운다 — [skip] 에 든 칸은 비워 둔다.
Future<void> _fillBasics(
  WidgetTester tester, {
  String year = '2000',
  String height = '170',
  String? phone,
  Set<String> skip = const {},
}) async {
  await _nickname(tester, _englishNickname(), _nicknameOk);
  await type(tester, input('예: 2003'), year);
  await type(tester, input('예: 170'), height);
  final digits = phone ?? '010${1000 + _random.nextInt(9000)}${1000 + _random.nextInt(9000)}';
  await type(tester, input('010-0000-0000'), digits.replaceAll('-', ''));
  if (!skip.contains('gender')) await tap(tester, find.widgetWithText(SelectChip, '남성'));
}

final Map<String, Area1Case> area1Cases = {
  'E-AUTH-05': _session((tester, job) async {
    await arrive(tester, 'login');
    await type(tester, input('hong@snu.ac.kr'), job['email'] as String);
    await tap(tester, button('인증 메일 받기'));
    await pumpUntil(tester, find.text(_rejected), timeout: const Duration(seconds: 15));
    must(await appears(tester, screen('code'), const Duration(seconds: 3)) == null, '인증 코드 화면으로 넘어감');
    return null;
  }),
  'E-AUTH-16': _session((tester, job) async {
    await arrive(tester, 'login');
    await type(tester, input('hong@snu.ac.kr'), job['email'] as String);
    await tap(tester, button('인증 메일 받기'));
    await arrive(tester, 'code');
    await type(tester, input('인증 코드 6자리'), '000000');
    await tap(tester, button('확인'));
    await pumpUntil(tester, find.text(_wrongCode), timeout: const Duration(seconds: 15));
    must(Supabase.instance.client.auth.currentSession == null, '틀린 코드로 로그인됨');
    return null;
  }),
  'E-AUTH-17': _session(_arriveAt),
  'E-AUTH-20': _session(_arriveAt),
  'E-AUTH-21': _session((tester, job) async {
    await arrive(tester, '04-1b');
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    await arrive(tester, 'login');
    await signIn(job['second'] as String);
    final watch = Stopwatch()..start();
    var sawFirst = false;
    while (screen('consent').evaluate().isEmpty) {
      must(watch.elapsed < const Duration(seconds: 30), '둘째 계정이 02-c 에 안 닿음');
      await tester.pump(const Duration(milliseconds: 100));
      sawFirst |= screen('04-1b').evaluate().isNotEmpty || screen('04-1').evaluate().isNotEmpty;
    }
    must(!sawFirst, '둘째 계정에 앞 계정의 온보딩 화면이 보임');
    return null;
  }),
  'E-GATE-01': _session((tester, job) async {
    await arrive(tester, 'consent');
    must(find.byType(BackButton).evaluate().isEmpty && find.byIcon(AppIcons.arrowLeft).evaluate().isEmpty, '뒤로 버튼이 있음');
    return null;
  }),
  'E-GATE-02': _session(_arriveAt),
  'E-GATE-03': _session((tester, job) async {
    await arrive(tester, 'suspended');
    must(button('로그아웃').evaluate().length == 1, '"로그아웃" 버튼 수 ${button('로그아웃').evaluate().length}');
    must(find.text('탈퇴하기').evaluate().length == 1, '"탈퇴하기" 없음');
    must(find.byType(AppBottomNav).evaluate().isEmpty, '하단 내비가 보임');
    return null;
  }),
  'E-GATE-07': _session((tester, job) async {
    await arrive(tester, 'consent');
    must(!enabled(tester, _consentCta), '처음부터 버튼이 켜짐');
    await _consentRow(tester, '이용약관');
    must(_checkedBoxes(tester) == 1, '이용약관이 안 켜짐');
    must(!enabled(tester, _consentCta), '필수 하나로 버튼이 켜짐');
    return null;
  }),
  'E-GATE-08': _session((tester, job) async {
    await arrive(tester, 'consent');
    await _consentRow(tester, '이용약관');
    await _consentRow(tester, '개인정보 수집·이용');
    await tap(tester, button(_consentCta));
    await arrive(tester, '3b', timeout: const Duration(seconds: 5));
    return null;
  }),
  'E-GATE-09': _session((tester, job) async {
    await arrive(tester, 'consent');
    await _consentRow(tester, '전체 동의');
    must(_checkedBoxes(tester) == 4, '전체 동의 뒤 켜진 칸 ${_checkedBoxes(tester)}');
    final tappedAt = DateTime.now().toUtc().toIso8601String();
    await tap(tester, button(_consentCta));
    await arrive(tester, '3b', timeout: const Duration(seconds: 10));
    return {'tapped_at': tappedAt};
  }),
  'E-GATE-10': _session((tester, job) async {
    await arrive(tester, 'consent');
    await _consentRow(tester, '전체 동의');
    await _consentRow(tester, '전체 동의');
    must(_checkedBoxes(tester) == 0, '두 번 누른 뒤 켜진 칸 ${_checkedBoxes(tester)}');
    await _consentRow(tester, '전체 동의');
    await _consentRow(tester, '마케팅 알림 받기');
    must(!_allAgreeChecked(tester), '마케팅을 껐는데 전체 동의가 켜져 있음');
    must(enabled(tester, _consentCta), '필수가 다 켜졌는데 버튼이 꺼짐');
    return null;
  }),
  'E-GATE-11': _session((tester, job) async {
    await arrive(tester, 'consent');
    Finder view(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '$label 보기');
    must(find.text('보기').evaluate().length == 2, '"보기" ${find.text('보기').evaluate().length}개');
    must(view('마케팅 알림 받기').evaluate().isEmpty, '마케팅 줄에 보기가 있음');
    // 누르고 바로 끝낸다 — 브라우저가 뜨면 앱이 멈춤(paused) 상태가 돼 pump 가 끝나지 않는다.
    // 브라우저가 맨 위인지는 PC 가 본다(e2e/area1.py p_gate_11).
    await tester.ensureVisible(view('이용약관'));
    await tester.pump();
    await tester.tap(view('이용약관'));
    return null;
  }),
  'E-GATE-13': _session((tester, job) async {
    await arrive(tester, 'consent');
    await _consentRow(tester, '이용약관');
    await _consentRow(tester, '개인정보 수집·이용');
    final cta = button(_consentCta).last;
    await tester.tap(cta);
    await tester.tap(cta, warnIfMissed: false); // 첫 누름의 프레임이 돌기 전에 한 번 더
    await arrive(tester, '3b', timeout: const Duration(seconds: 10));
    return null;
  }),
  'E-GATE-14': _session((tester, job) async {
    await arrive(tester, 'consent');
    await tap(tester, find.text('로그아웃'));
    await pumpUntil(tester, find.text('로그아웃할까요?'), timeout: const Duration(seconds: 5));
    // 시트의 확인 버튼은 AppButton 이 아니라 SafetySheetButton 이다(confirm_sign_out → showSafetyConfirmSheet).
    // 02-c 아래의 로그아웃은 글자 버튼이라 이 찾기에 안 걸린다 — 10-04 실폰 GATE-14 "No element" 원인.
    await tap(tester, find.widgetWithText(SafetySheetButton, '로그아웃'));
    await arrive(tester, 'login', timeout: const Duration(seconds: 10));
    must(Supabase.instance.client.auth.currentSession == null, '세션이 남아 있음');
    return null;
  }),
  'E-GATE-30': _session((tester, job) async {
    await arrive(tester, '3b');
    await _fakeGallery(tester);
    await _realName(tester, '김', on: false);
    await _realName(tester, '김철', on: true);
    return null;
  }),
  'E-GATE-31': _session((tester, job) async {
    await arrive(tester, '3b');
    await _fakeGallery(tester);
    for (final name in ['김1', '김ㄱ']) {
      await _realName(tester, name, on: false);
      must(find.text(realNameRuleMessage).evaluate().isNotEmpty, '"$name" 에 안내 문구 없음');
    }
    return null;
  }),
  'E-GATE-32': _session((tester, job) async {
    await arrive(tester, '3b');
    await _fakeGallery(tester);
    await _realName(tester, '가' * 30, on: true);
    await _realName(tester, '가' * 31, on: false);
    await _realName(tester, 'Jun seok', on: true);
    return null;
  }),
  'E-GATE-52': _session((tester, job) async {
    await arrive(tester, '3c');
    must(find.text(job['university'] as String).evaluate().length == 1, '학교 이름 "${job['university']}" 이 1줄이 아님');
    must(find.text('확인됨').evaluate().isNotEmpty, '"확인됨" 없음');
    must(input('예: 컴퓨터공학과').evaluate().isNotEmpty, '학과 칸 없음');
    return null;
  }),
  'E-GATE-53': _session((tester, job) async {
    await arrive(tester, '3c');
    final department = input('예: 컴퓨터공학과');
    final number = input('예: 21');
    for (final (dept, no, on) in [
      ('', '21', false),
      ('컴퓨터공학과', '', false),
      ('가' * 31, '21', false),
      ('컴퓨터공학과', '1' * 21, false),
      ('가' * 30, '1' * 20, true),
    ]) {
      await type(tester, department, dept);
      await type(tester, number, no);
      must(enabled(tester, '다음') == on, '학과 ${dept.length}자 · 학번 ${no.length}자에 다음이 ${on ? '꺼짐' : '켜짐'}');
    }
    return null;
  }),
  'E-GATE-54': _session((tester, job) async {
    await arrive(tester, '3c');
    await type(tester, input('예: 컴퓨터공학과'), '컴퓨터공학과');
    await type(tester, input('예: 21'), '21');
    await tap(tester, button('다음'));
    await arrive(tester, '04-1', timeout: const Duration(seconds: 5));
    return null;
  }),
  // 첫 켬: 3c 에서 10초(그동안 토큰 등록) → PC 가 1행 확인. 다시 켬: 저장해 04-1 로 → 10초 → PC 가 같은 1행 확인.
  'E-GATE-56': _session((tester, job) async {
    await arrive(tester, '3c');
    if (!_fresh(job)) {
      await type(tester, input('예: 컴퓨터공학과'), '컴퓨터공학과');
      await type(tester, input('예: 21'), '21');
      await tap(tester, button('다음'));
      await arrive(tester, '04-1', timeout: const Duration(seconds: 10));
    }
    await wait(tester, const Duration(seconds: 10));
    return null;
  }),
  'E-ONB-01': _session((tester, job) async {
    await arrive(tester, '04-1');
    final took = <int>[];
    for (final nickname in [_koreanNickname(), _englishNickname()]) {
      await type(tester, labeled('닉네임'), nickname);
      final at = await appears(tester, find.text(_nicknameOk), const Duration(seconds: 5));
      must(at != null, '"$nickname" 에 초록 문구 없음');
      took.add(at!.inMilliseconds);
    }
    must(took.every((ms) => ms <= 1000), '1초 넘게 걸림 $took ms');
    return {'note': '$took ms'};
  }),
  // 숫자 · 띄어쓰기는 입력칸이 걸러 낸다(nicknameInputFormatters) — 남은 1자에 같은 문구가 나와야 한다.
  'E-ONB-02': _session((tester, job) async {
    await arrive(tester, '04-1');
    // 앞 값과 걸러진 글자가 같으면 onChanged 가 안 돈다 — '가 '(→ '가')는 'ㄱㄴ' 뒤에 둔다.
    for (final nickname in ['가', '가나다라마바', '가1', 'ㄱㄴ', '가 ']) {
      await _nickname(tester, nickname, _nicknameBad);
      must(!RegExp(r'[0-9 ]').hasMatch(fieldText(tester, labeled('닉네임'))), '"$nickname" 의 숫자 · 띄어쓰기가 들어감');
      must(!enabled(tester, '다음'), '"$nickname" 에 다음이 켜짐');
    }
    return null;
  }),
  'E-ONB-03': _session((tester, job) async {
    await arrive(tester, '04-1');
    final taken = job['nickname'] as String;
    for (final nickname in [taken, taken.toLowerCase()]) {
      await _nickname(tester, nickname, _nicknameTaken);
      must(!enabled(tester, '다음'), '"$nickname" 에 다음이 켜짐');
    }
    return null;
  }),
  'E-ONB-04': _session((tester, job) async {
    await arrive(tester, '04-1');
    await _nickname(tester, job['nickname'] as String, _nicknameOk);
    return null;
  }),
  'E-ONB-06': _session((tester, job) async {
    await arrive(tester, '04-1');
    final youngest = job['year'] as int;
    await _fillBasics(tester, year: '$youngest');
    must(find.text('$youngest년생부터 가입할 수 있어요').evaluate().isEmpty, '$youngest 에 문구가 보임');
    must(enabled(tester, '다음'), '$youngest 에 다음이 꺼짐');
    await type(tester, input('예: 2003'), '${youngest + 1}');
    must(find.text('$youngest년생부터 가입할 수 있어요').evaluate().isNotEmpty, '${youngest + 1} 에 문구 없음');
    must(!enabled(tester, '다음'), '${youngest + 1} 에 다음이 켜짐');
    return null;
  }),
  'E-ONB-07': _session((tester, job) async {
    await arrive(tester, '04-1');
    await _fillBasics(tester, year: '1950');
    must(enabled(tester, '다음'), '1950 에 다음이 꺼짐');
    await type(tester, input('예: 2003'), '1949');
    must(!enabled(tester, '다음'), '1949 에 다음이 켜짐');
    must(find.textContaining('년생부터').evaluate().isEmpty, '1949 에 오류 문구가 보임');
    return null;
  }),
  'E-ONB-10': _session((tester, job) async {
    await arrive(tester, '04-1');
    await _fillBasics(tester);
    for (final (height, ok) in [('120', true), ('230', true), ('119', false), ('231', false)]) {
      await type(tester, input('예: 170'), height);
      must(find.text(_heightBad).evaluate().isEmpty == ok, '키 $height 문구가 ${ok ? '보임' : '없음'}');
      must(enabled(tester, '다음') == ok, '키 $height 에 다음이 ${ok ? '꺼짐' : '켜짐'}');
    }
    return null;
  }),
  'E-ONB-11': _session((tester, job) async {
    await arrive(tester, '04-1');
    final phone = job['phone'] as String;
    await _fillBasics(tester, phone: phone);
    await tap(tester, button('다음'));
    await arrive(tester, '04-1b', timeout: const Duration(seconds: 10));
    final digits = phone.replaceAll('-', '');
    must(find.textContaining(digits.substring(3)).evaluate().isEmpty && find.textContaining(phone).evaluate().isEmpty,
        '04-1b 에 번호 원문이 보임');
    return null;
  }),
  'E-ONB-12': _session((tester, job) async {
    await arrive(tester, '04-1');
    await _fillBasics(tester, phone: '0101234567');
    must(!enabled(tester, '다음'), '10자리 번호에 다음이 켜짐');
    return null;
  }),
  // 옛 10자리(011-123-4567)는 앱이 못 받는다. 서버가 받는지는 PC 가 API 로 본다.
  'E-ONB-13': _session((tester, job) async {
    await arrive(tester, '04-1');
    await _fillBasics(tester, phone: '0111234567');
    must(!enabled(tester, '다음'), '011 10자리에 다음이 켜짐');
    return null;
  }),
  'E-ONB-15': _session((tester, job) async {
    await arrive(tester, '04-1');
    await _fillBasics(tester, skip: {'gender'});
    must(!enabled(tester, '다음'), '성별 없이 다음이 켜짐');
    return null;
  }),
  'E-ONB-16': _session((tester, job) async {
    await arrive(tester, '04-1');
    await _fillBasics(tester);
    await tap(tester, find.widgetWithText(SelectChip, '모름'));
    await tap(tester, button('다음'));
    await arrive(tester, '04-1b', timeout: const Duration(seconds: 10));
    return null;
  }),
  'E-ONB-17': _session((tester, job) async {
    await arrive(tester, '04-1');
    await _fillBasics(tester);
    for (final pole in ['E', 'N', 'T']) {
      await tap(tester, find.widgetWithText(SelectChip, pole));
    }
    // 경고 문구 0 — 화면에 MBTI 글자는 칸 이름 "내 MBTI" 하나뿐이어야 한다.
    must(find.textContaining('MBTI').evaluate().length == 1, '세 축만 골랐는데 MBTI 안내가 보임');
    await tap(tester, button('다음'));
    await arrive(tester, '04-1b', timeout: const Duration(seconds: 10));
    return null;
  }),
  'E-ONB-18': _session((tester, job) async {
    await arrive(tester, '04-1b');
    final field = input('예: campusmate_22');
    await type(tester, field, '   ');
    must(!enabled(tester, '다음'), '공백뿐인데 다음이 켜짐');
    await type(tester, field, job['kakao'] as String);
    await tap(tester, button('다음'));
    await arrive(tester, '04-2', timeout: const Duration(seconds: 10));
    return null;
  }),
  ..._b2Cases,
  ..._b3Cases,
  ..._b4Cases,
  ..._emuCases,
};
