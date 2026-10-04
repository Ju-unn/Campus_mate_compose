import 'dart:io';

import 'package:campus_mate/account/view/account_screen.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/faq/view/faq_screen.dart';
import 'package:campus_mate/referral/view/invite_friends_sheet.dart';
import 'package:campus_mate/safety/view/block_list_screen.dart';
import 'package:campus_mate/safety/view/contact_block_list_screen.dart';
import 'package:campus_mate/safety/view/contact_picker_screen.dart';
import 'package:campus_mate/safety/view/contact_row.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:campus_mate/safety/viewmodel/contact_picker_view_model.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'support.dart';

part 'area3_contacts.dart';
part 'area4_contacts.dart';
part 'area4_set2.dart';

/// 영역 4 SET 1차 — 설정 16 · 알림 설정 16d · 계정 16e · 카톡 16e-1 · 차단 목록 16f. PC 쪽은 e2e/area4.py 의 같은 번호.
/// 화면 글자는 시나리오가 아니라 지금 화면 코드(frontend/lib/matching · account · safety)에서 옮겼다.
/// 망을 끊고 켜는 것은 PC 가 한다 — 앱은 [step] 에서 멈춰 PC 가 끝내고 go 를 넣기를 기다린다.

const _networkDown = '네트워크 연결을 확인해 주세요';
const _dash = '—';

/// 설정 16 의 줄(위 → 아래).
const _settingsRows = [
  '매칭 활성화', '무료로 하트 모으기', '친구 초대', '계정', '알림', '차단 목록', '연락처 차단', '자주 묻는 질문', '이용약관',
  '개인정보처리방침', '로그아웃', '탈퇴하기',
];

/// 16d 에 보이는 것(위 → 아래) — 섹션 머리글 4개와 스위치 8개. 스위치는 서버 칸 이름으로 짝을 짓는다.
const _screen16d = [
  '매칭', '오늘의 카드 도착', '받은 수락', '매칭 성립', '대화', '새 메시지', '신뢰 확인 리마인드', '지인 리뷰·커뮤니티', '새 지인 리뷰',
  '기타', '혜택·이벤트 소식', '방해 금지 시간 (22:00 ~ 08:00)',
];
const _switchTitles = {
  'card_arrived': '오늘의 카드 도착', 'acceptance_received': '받은 수락', 'match_made': '매칭 성립', 'new_message': '새 메시지',
  'trust_reminder': '신뢰 확인 리마인드', 'new_friend_review': '새 지인 리뷰', 'marketing': '혜택·이벤트 소식',
  'quiet_hours': '방해 금지 시간 (22:00 ~ 08:00)',
};
const _switchDefaults = {
  'card_arrived': true, 'acceptance_received': true, 'match_made': true, 'new_message': true, 'trust_reminder': true,
  'new_friend_review': true, 'marketing': false, 'quiet_hours': true,
};
const _cardException = '오늘의 카드 도착 알림은 방해 금지 시간에도 보내드려요. 카드가 도착하는 시각이 아침 7시예요.';

const _kakaoLabel = '카카오톡 아이디';
const _unblockDescription = '이 상대가 다시 카드에 나타날 수 있어요. 사라진 대화는 돌아오지 않아요.';

/// 앞 가설의 세션을 지우고([fresh] 가 false 면 그대로 둔다) 일감의 토큰으로 로그인한 뒤 [body] 를 돈다.
Area1Case _session(Area1Case body) => (tester, job) async {
      if (job['fresh'] != false) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

/// 앱바 제목 — 아래 깔린 화면은 가려져(offstage) 안 잡힌다.
Finder _screenTitle(String title) => find.descendant(of: find.byType(AppBar), matching: find.text(title));

Finder _tile(String title) => find.widgetWithText(SwitchListTile, title);

bool _on(WidgetTester tester, String title) => tester.widget<SwitchListTile>(_tile(title)).value;

ScrollableState _list(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first);

Future<void> _toTop(WidgetTester tester) async {
  _list(tester).position.jumpTo(0);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _toBottom(WidgetTester tester) async {
  final position = _list(tester).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pump(const Duration(milliseconds: 200));
}

/// 목록은 느긋하게 그려져 화면 밖 줄은 아직 없을 수 있다 — 없으면 아래로 밀어 찾는다. 위에서 아래로 차례로만 부른다.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
}

/// 홈 → 나 탭 → 톱니바퀴 → 설정 16.
Future<void> _openSettings(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byIcon(AppIcons.settings));
  await tap(tester, find.byIcon(AppIcons.settings));
  await arrive(tester, 'settings');
}

/// 설정의 [row] 줄을 눌러 앱바 제목이 [title] 인 화면까지.
Future<void> _openFromSettings(WidgetTester tester, String row, String title) async {
  await _openSettings(tester);
  await _reveal(tester, find.text(row));
  await tap(tester, find.text(row));
  await pumpUntil(tester, _screenTitle(title));
}

/// [texts] 가 모두 화면에 있을 때까지(글자 일부만 맞아도 된다 — 학교 이름처럼 RichText 안에 든 것까지).
Future<void> _seeAll(WidgetTester tester, List<String> texts, {Duration timeout = const Duration(seconds: 15)}) async {
  final watch = Stopwatch()..start();
  List<String> missing() => [for (final t in texts) if (find.textContaining(t, findRichText: true).evaluate().isEmpty) t];
  while (missing().isNotEmpty) {
    must(watch.elapsed < timeout, '${timeout.inSeconds}초 안에 화면에 안 나옴: ${missing()}');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// 16e 계정 화면 안에서만 [texts] 를 찾는다 — 16e-1 입력칸(EditableText)의 글자와 섞이지 않게(저장 · 뒤로 가는 전환 중에는 둘 다 떠 있다).
Future<void> _seeInAccount(WidgetTester tester, List<String> texts, {Duration timeout = const Duration(seconds: 15)}) async {
  final watch = Stopwatch()..start();
  Finder inAccount(String text) =>
      find.descendant(of: find.byType(AccountScreen), matching: find.textContaining(text, findRichText: true));
  List<String> missing() => [for (final t in texts) if (inAccount(t).evaluate().isEmpty) t];
  while (missing().isNotEmpty) {
    must(watch.elapsed < timeout, '${timeout.inSeconds}초 안에 16e 에 안 나옴: ${missing()}');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _expectValue(WidgetTester tester, String title, bool expected,
    {Duration timeout = const Duration(seconds: 15)}) async {
  final watch = Stopwatch()..start();
  while (_tile(title).evaluate().isEmpty || _on(tester, title) != expected) {
    must(watch.elapsed < timeout, '$title 가 ${expected ? '켜짐' : '꺼짐'}이 아님');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

typedef _Walk16d = ({Map<String, bool> values, bool comment});

/// 16d 를 위에서 아래로 한 번 훑어 본 것 — 스위치 값 8개와 "댓글" 글자가 있었는지.
Future<_Walk16d> _walk16d(WidgetTester tester) async {
  await _toTop(tester);
  final values = <String, bool>{};
  var comment = false;
  for (final text in _screen16d) {
    await _reveal(tester, find.text(text));
    comment |= find.textContaining('댓글').evaluate().isNotEmpty;
    for (final entry in _switchTitles.entries) {
      if (entry.value == text) values[entry.key] = _on(tester, text);
    }
  }
  return (values: values, comment: comment);
}

Future<void> _open16d(WidgetTester tester) => _openFromSettings(tester, '알림', '알림');

Future<void> _openAccount(WidgetTester tester) => _openFromSettings(tester, '계정', '계정');

/// 계정 → 카카오톡 줄 → 16e-1. 저장된 아이디([job] 의 kakao, 없으면 빈칸)가 채워질 때까지 기다린다.
Future<void> _openKakao(WidgetTester tester, Map<String, dynamic> job) async {
  await _openAccount(tester);
  await pumpUntil(tester, find.text('인증 완료'));
  await tap(tester, find.text(_kakaoLabel));
  await pumpUntil(tester, find.text('신뢰 확인을 마친 상대에게만 공개돼요.'));
  final watch = Stopwatch()..start();
  final expected = (job['kakao'] as String?) ?? '';
  while (fieldText(tester, labeled(_kakaoLabel)) != expected) {
    must(watch.elapsed < const Duration(seconds: 15), '16e-1 입력칸이 "$expected" 로 안 채워짐(${fieldText(tester, labeled(_kakaoLabel))})');
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _openBlockList(WidgetTester tester) => _openFromSettings(tester, '차단 목록', '차단 목록');

int _blockedRows() => find.byKey(blockedRowKey).evaluate().length;

final Map<String, Area1Case> area4Cases = {
  ..._set2Cases,
  ..._contactsCases,
  ..._safeContactsCases,
  'E-SET-01': _session((tester, job) async {
    await _openSettings(tester);
    await pumpUntil(tester, find.text('자주 묻는 질문'));
    var previous = -1.0;
    for (final row in _settingsRows) {
      await _reveal(tester, find.text(row));
      final y = tester.getTopLeft(find.text(row).first).dy + _list(tester).position.pixels;
      must(y > previous, '$row 가 앞 줄보다 위에 있음');
      previous = y;
    }
    return null;
  }),
  'E-SET-05': _session((tester, job) async {
    await _openSettings(tester);
    await _expectValue(tester, '매칭 활성화', !(job['paused'] as bool));
    return null;
  }),
  'E-SET-06': _session((tester, job) async {
    await _openSettings(tester);
    await _expectValue(tester, '매칭 활성화', true);
    await step('online');
    await tap(tester, _tile('매칭 활성화'));
    await pumpUntil(tester, find.text(_networkDown), timeout: const Duration(seconds: 20));
    await _expectValue(tester, '매칭 활성화', true, timeout: const Duration(seconds: 5));
    return null;
  }),
  'E-SET-07': _session((tester, job) async {
    await _open16d(tester);
    final walk = await _walk16d(tester);
    must(walk.values.length == 8, '스위치 ${walk.values.length}개(기대 8)');
    must(mapEquals(walk.values, _switchDefaults), '스위치 값 ${walk.values}(기대 $_switchDefaults)');
    return null;
  }),
  'E-SET-09': _session((tester, job) async {
    await _open16d(tester);
    if (job['flip'] case final List flip) {
      await _toTop(tester);
      for (final key in flip.cast<String>()) {
        await _reveal(tester, _tile(_switchTitles[key]!));
        await tap(tester, _tile(_switchTitles[key]!));
      }
      await wait(tester, const Duration(seconds: 3)); // 서버 저장이 끝나기를
      return null;
    }
    final expected = (job['switches'] as Map).cast<String, bool>();
    final watch = Stopwatch()..start();
    var got = (await _walk16d(tester)).values;
    while (!mapEquals(got, expected)) {
      must(watch.elapsed < const Duration(seconds: 20), '다시 켠 뒤 스위치 $got(기대 $expected)');
      got = (await _walk16d(tester)).values;
    }
    return null;
  }),
  'E-SET-10': _session((tester, job) async {
    await _open16d(tester);
    await _expectValue(tester, '새 메시지', true);
    await step('online');
    await tap(tester, _tile('새 메시지'));
    await wait(tester, const Duration(seconds: 4));
    await _expectValue(tester, '새 메시지', true, timeout: const Duration(seconds: 5));
    final watch = Stopwatch()..start();
    while (find.text(_networkDown).evaluate().isEmpty) {
      must(watch.elapsed < const Duration(seconds: 15), '빨간 글 "$_networkDown" 이 안 나옴');
      await _toBottom(tester);
    }
    return null;
  }),
  'E-SET-11': _session((tester, job) async {
    await _open16d(tester);
    await pumpUntil(tester, find.text('오늘의 카드 도착'));
    await _toBottom(tester);
    await pumpUntil(tester, find.text(_cardException), timeout: const Duration(seconds: 5));
    must(find.textContaining('채팅').evaluate().isEmpty, '채팅 예외 안내가 있음');
    return null;
  }),
  'E-SET-13': _session((tester, job) async {
    await _open16d(tester);
    must(!(await _walk16d(tester)).comment, '"댓글" 줄이 있음');
    return null;
  }),
  'E-SET-14': _session((tester, job) async {
    await _openAccount(tester);
    await _seeAll(tester, (job['texts'] as List).cast<String>());
    await _seeAll(tester, ['실명과 출생연도는 학생증 대조와 운영 확인에만 쓰여요. 다른 사용자에게는 닉네임만 보여요.']);
    return null;
  }),
  'E-SET-15': _session((tester, job) async {
    await _openAccount(tester);
    await _seeAll(tester, [job['date'] as String]);
    return null;
  }),
  'E-SET-16': _session((tester, job) async {
    await _openAccount(tester);
    await pumpUntil(tester, find.text('인증 완료'));
    final dashes = find.text(_dash).evaluate().length;
    must(dashes == job['dashes'], '"$_dash" $dashes개(기대 ${job['dashes']})');
    return null;
  }),
  'E-SET-17': _session((tester, job) async {
    await _openSettings(tester);
    await _reveal(tester, find.text('계정'));
    await step('cut');
    await tap(tester, find.text('계정'));
    await pumpUntil(tester, find.text('잠시 뒤 다시 시도해 주세요'), timeout: const Duration(seconds: 20));
    must(button('다시 시도').evaluate().isNotEmpty, '"다시 시도" 버튼이 없음');
    await step('restore');
    await tap(tester, button('다시 시도'));
    await _seeAll(tester, ['학생 인증', '인증 완료'], timeout: const Duration(seconds: 30));
    return null;
  }),
  'E-SET-18': _session((tester, job) async {
    await _openKakao(tester, job);
    await _seeAll(tester, ['신뢰 확인을 마친 상대에게만 공개돼요.', '꼭 확인해 주세요']);
    return null;
  }),
  'E-SET-19': _session((tester, job) async {
    await _openKakao(tester, job);
    await type(tester, labeled(_kakaoLabel), job['value'] as String);
    await tap(tester, button('저장'));
    await pumpUntil(tester, find.text('인증 완료')); // 저장하면 16e 로 돌아와 다시 읽는다
    await _seeInAccount(tester, [job['value'] as String]);
    return null;
  }),
  'E-SET-20': _session((tester, job) async {
    await _openKakao(tester, job);
    await type(tester, labeled(_kakaoLabel), '');
    must(!enabled(tester, '저장'), '전부 지웠는데 저장이 눌림');
    await type(tester, labeled(_kakaoLabel), '   ');
    must(!enabled(tester, '저장'), '공백 3개인데 저장이 눌림');
    return null;
  }),
  'E-SET-21': _session((tester, job) async {
    await _openKakao(tester, job);
    await type(tester, labeled(_kakaoLabel), job['value'] as String);
    await tap(tester, button('저장'));
    await pumpUntil(tester, find.text('인증 완료'));
    return null;
  }),
  'E-SET-22': _session((tester, job) async {
    await _openKakao(tester, job);
    await step('online');
    await type(tester, labeled(_kakaoLabel), job['value'] as String);
    await tap(tester, button('저장'));
    await pumpUntil(tester, find.text(_networkDown), timeout: const Duration(seconds: 20));
    must(_screenTitle(_kakaoLabel).evaluate().isNotEmpty, '16e-1 을 벗어남');
    return null;
  }),
  'E-SET-23': _session((tester, job) async {
    await _openKakao(tester, job);
    await type(tester, labeled(_kakaoLabel), job['value'] as String);
    await tap(tester, find.byType(BackButton));
    await pumpUntil(tester, find.text('인증 완료'));
    await _seeInAccount(tester, [(job['kakao'] as String?) ?? _dash]);
    return null;
  }),
  'E-SET-24': _session((tester, job) async {
    await _openBlockList(tester);
    await _seeAll(tester, ['아직 차단한 상대가 없어요', '신고하거나 차단한 상대가 있으면\n여기에 모여요.']);
    return null;
  }),
  'E-SET-25': _session((tester, job) async {
    await _openBlockList(tester);
    await pumpUntil(tester, find.byKey(blockedRowKey));
    final nicknames = (job['nicknames'] as List).cast<String>();
    await _seeAll(tester, nicknames);
    must(_blockedRows() == nicknames.length, '줄 ${_blockedRows()}개(기대 ${nicknames.length})');
    final dates = (job['dates'] as List).cast<String>();
    final dated = [for (final d in dates) find.text('$d 차단').evaluate().length].fold(0, (a, b) => a + b);
    must(dated == nicknames.length, '"날짜 차단" 글자 $dated개(기대 ${nicknames.length}, 후보 $dates)');
    await _seeAll(tester, ['차단하면 그 대화는 내 목록에서 사라져요.', '연락처로 차단한 지인은 여기가 아니라 설정 > 연락처 차단에서 관리해요.']);
    must(find.textContaining('신고').evaluate().isEmpty && find.textContaining('사유').evaluate().isEmpty, '신고 · 사유 구분 글이 있음');
    return null;
  }),
  'E-SET-27': _session((tester, job) async {
    await _openBlockList(tester);
    await pumpUntil(tester, find.byKey(blockedRowKey));
    final rows = _blockedRows();
    await tap(tester, find.widgetWithText(TextButton, '해제').first);
    await pumpUntil(tester, find.text('차단을 해제할까요?'));
    await _seeAll(tester, [_unblockDescription]);
    await tap(tester, find.widgetWithText(SafetySheetButton, '취소'));
    await wait(tester, const Duration(seconds: 1));
    must(find.text('차단을 해제할까요?').evaluate().isEmpty, '취소했는데 시트가 남음');
    must(_blockedRows() == rows, '줄 ${_blockedRows()}개(기대 $rows)');
    return null;
  }),
  'E-SET-28': _session((tester, job) async {
    await _openBlockList(tester);
    await pumpUntil(tester, find.byKey(blockedRowKey));
    await tap(tester, find.widgetWithText(TextButton, '해제').first);
    await pumpUntil(tester, find.text('차단을 해제할까요?'));
    await tap(tester, find.widgetWithText(SafetySheetButton, '해제'));
    await pumpUntil(tester, find.text('아직 차단한 상대가 없어요'), timeout: const Duration(seconds: 15));
    return null;
  }),
};
