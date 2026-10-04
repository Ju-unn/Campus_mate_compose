import 'dart:math';

import 'package:campus_mate/billing/view/heart_task_row.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/home/view/cohort_wait_view.dart';
import 'package:campus_mate/home/view/home_screen.dart';
import 'package:campus_mate/home/view/mosaic_rail.dart';
import 'package:campus_mate/home/view/stat_tile.dart';
import 'package:campus_mate/home/view/tag.dart';
import 'package:campus_mate/matching/view/notification_settings_screen.dart';
import 'package:campus_mate/matching/viewmodel/notification_settings_view_model.dart';
import 'package:campus_mate/referral/view/invite_friends_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'support.dart';

/// 영역 2 폰 A 한 대 1차 16(홈 09b · 추천 시트 16i · 알림 설정 16d · 하트 목록 18a/18b 읽기). PC 쪽은 e2e/area2_phone.py 의
/// 같은 번호 — 홈 계정을 만들어 1회용 토큰을 넘기고 DB 값을 본다. 화면 글자는 시나리오가 아니라 지금 화면 코드에서 옮겼다.
/// 찾기는 Key 없이 화면 글자 · 툴팁 · 공용/화면 위젯 종류로 한다. 제출 · 공유 같은 쓰기 버튼은 누르지 않는다.

// 09b 메인 — frontend/lib/home/view/home_screen.dart
const _heroLines = ['오늘의 카드가', '도착했어요']; // _HeroToday :162-163
const _heroCta = '지금 확인하기'; // :179
const _railTitle = '지금 함께 있는 사람들'; // _RailHeader :202 — 요약을 받아야 그려지는 첫 줄
const _campusTitle = '참여 중인 대학'; // :109
const _statLabels = ['전달된 카드', '가입 수', '시작된 대화']; // StatTile label :78 · 88 · 97
const _statEmpty = '첫 기록이 쌓이는 중이에요'; // _StatEmptyPanel :232
const _completionLead = '프로필 완성도'; // _ProfileNudge :361 '프로필 완성도 $percent%'
const _reviewRating = '4.8'; // _ReviewStrip :270 rating.toStringAsFixed(1) — 목값 http_home_repository.dart:21
const _reviewCount = '(143명 평가)'; // :280 '($count명 평가)' — 목값 :22
const _cohortLead = '우리 학교 첫 카드까지'; // cohort_wait_view.dart:203 '우리 학교 첫 카드까지 · $dayLabel'
const _todayTitle = '오늘의 카드'; // today_cards_screen.dart:36 앱바
// 하트 재화 그림(DESIGN §5.4 — Lucide 가 아니라 이미지). heart_task_row.dart:11 · avatar_regen_sheet.dart:102 · 묶음 · 단계 그림.
final _currencyAsset = RegExp(r'heart-(flat|tier|bundle)');

// 설정 16 — frontend/lib/matching/view/settings_screen.dart
const _heartTasksRow = '무료로 하트 모으기'; // :69
const _inviteRow = '친구 초대'; // :74
const _inviteNote = '내 추천 코드를 친구에게 보내요'; // :75
const _notificationsRow = '알림'; // :84

// 16i — frontend/lib/referral/view/invite_friends_sheet.dart
const _inviteBody = '친구가 가입할 때 이 코드를 넣으면 둘 다 하트 50개를 받아요.'; // :35
const _copy = '복사'; // _CopyButton :223
const _copied = '코드를 복사했어요'; // :61
const _close = '닫기'; // :140

// 16d — frontend/lib/matching/view/notification_settings_screen.dart _sections :16-75. 기본값 = cards/repository.py NOTIFICATION_DEFAULTS.
const _notificationDefaults = {
  '오늘의 카드 도착': true,
  '받은 수락': true,
  '매칭 성립': true,
  '새 메시지': true,
  '신뢰 확인 리마인드': true,
  '새 지인 리뷰': true,
  '혜택·이벤트 소식': false,
  '방해 금지 시간 (22:00 ~ 08:00)': true,
};

// 18a — frontend/lib/billing/view/heart_tasks_screen.dart · heart_task_row.dart
const _rewardNotice = '초기 보상 기준 · 인증 후 지급\n100명 이후 홍보 30 / 단톡방 20 하트'; // heart_tasks_screen.dart:17
const _taskOrder = 'everytime_post,kakao_share,poll_vote'; // 서버 TASK_ORDER(heart_tasks/router.py:23)
// 줄마다 보여야 할 글(heart_task_row.dart _title :87-91 · _rewardText :94-96 · "매일" :165 · 버튼 :101).
const _taskRows = [
  ['에브리타임 홍보', '50 · 월 1회', '인증하기'],
  ['학교 단톡방 공유', '25 · 월 3회', '인증하기'],
  ['커뮤니티 투표', '매일', '10 · 주 최대 30', '참여'],
];

// 18b — frontend/lib/billing/view/heart_task_submit_screen.dart
const _submitTitle = '인증샷 제출'; // :103
const _submitGuide = '스크린샷을 첨부하면 확인 후 하트를 드려요'; // :19
const _dateHint = '날짜가 보이게 찍어 주세요'; // :22 — 에브리타임만
const _submit = '제출하기'; // :131

/// 앞 가설의 세션을 지우고([fresh] 가 false 면 그대로 둔다) 일감의 토큰으로 로그인한 뒤 [body] 를 돈다(area1.dart 와 같은 모양).
Area1Case _session(Area1Case body) => (tester, job) async {
      if (job['fresh'] != false) {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      }
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

Finder _inHome(Finder finder) => find.descendant(of: find.byType(HomeScreen), matching: finder);

/// 메인 본문의 세로 목록.
Finder get _homeList =>
    _inHome(find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)).first;

/// 메인에 닿아 요약이 그려질 때까지(레일 제목 또는 19 대기 화면). 대기 화면이면 true.
Future<bool> _homeLoaded(WidgetTester tester) async {
  await arrive(tester, 'home');
  final rail = _inHome(find.text(_railTitle));
  final cohort = _inHome(find.byType(CohortWaitView));
  final watch = Stopwatch()..start();
  while (rail.evaluate().isEmpty && cohort.evaluate().isEmpty) {
    must(watch.elapsed < const Duration(seconds: 30), '30초 안에 메인 요약이 안 그려짐(/home/summary 실패?)');
    await tester.pump(const Duration(milliseconds: 200));
  }
  return cohort.evaluate().isNotEmpty;
}

/// 09b 를 볼 수 있을 때까지. 학교가 아직 안 열렸으면(19 대기 화면) 판정할 수 없다.
Future<void> _summary(WidgetTester tester) async {
  if (await _homeLoaded(tester)) throw E2eBlocked('시험대학이 아직 안 열림(19 대기 화면) — 09b 를 볼 수 없다');
}

/// 메인 목록을 위에서 끝까지 반 화면씩 내리며 [finders] 마다 한 자리에서 보인 가장 많은 개수를 센다.
/// 목록은 화면 밖 칸을 만들지 않아(찾기에 안 걸린다) 한 자리에서 다 볼 수 없다. [each] 는 자리마다 한 번.
Future<Map<String, int>> _sweep(WidgetTester tester, Map<String, Finder> finders, {void Function()? each}) async {
  final most = {for (final name in finders.keys) name: 0};
  final position = tester.state<ScrollableState>(_homeList).position;
  position.jumpTo(0);
  for (var stop = 0; stop < 20; stop++) {
    await tester.pump(const Duration(milliseconds: 200));
    for (final MapEntry(:key, :value) in finders.entries) {
      most[key] = max(most[key]!, value.evaluate().length);
    }
    each?.call();
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(min(position.pixels + position.viewportDimension / 2, position.maxScrollExtent));
  }
  return most;
}

/// 메인 완성도 카드 — [job] 의 percent 가 100 이면 카드가 없어야 하고, 아니면 "프로필 완성도 N%" 가 한 번.
Future<Map<String, Object?>?> _completion(WidgetTester tester, Map<String, dynamic> job) async {
  await _summary(tester);
  final percent = job['percent'] as int;
  final lines = _inHome(find.textContaining(_completionLead));
  final shown = <String>{};
  final seen = await _sweep(tester, {'card': lines, 'exact': _inHome(find.text('$_completionLead $percent%'))},
      each: () => shown.addAll(tester.widgetList<Text>(lines).map((t) => t.data ?? '')));
  if (percent == 100) {
    must(seen['card'] == 0, '넷 다 채웠는데 완성도 카드가 보임 $shown');
  } else {
    must(seen['exact'] == 1, '"$_completionLead $percent%" 가 아님 — 보인 글 $shown');
  }
  return null;
}

String _asset(ImageProvider image) => switch (image) {
      ResizeImage(:final imageProvider) => _asset(imageProvider),
      AssetImage(:final assetName) => assetName,
      ExactAssetImage(:final assetName) => assetName,
      _ => '',
    };

/// 하단 내비의 탭([label] = 메인 · 오늘 · 커뮤니티 · 대화 · 나).
Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

/// 메인 → 나 → 톱니(설정). 설정은 나 탭 위에 쌓인다.
Future<void> _openSettings(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byTooltip('설정'), timeout: const Duration(seconds: 10));
  await tap(tester, find.byTooltip('설정'));
  await arrive(tester, 'settings', timeout: const Duration(seconds: 5));
  await wait(tester, const Duration(milliseconds: 500)); // 넘김 애니메이션이 끝나게
}

Finder get _sheet => find.byType(InviteFriendsSheet);

/// 시트의 코드 글자 — 모양 판정(0 · O · 1 · I 없음)은 PC 가 하므로 여기선 넓게 대문자 · 숫자 6자.
Finder get _code => find.descendant(
      of: _sheet,
      matching: find.byWidgetPredicate((w) => w is Text && RegExp(r'^[A-Z0-9]{6}$').hasMatch(w.data ?? '')),
    );

/// 설정 "친구 초대" → 16i 에 코드가 뜰 때까지. 뜬 코드를 돌려준다.
Future<String> _openInvite(WidgetTester tester) async {
  await tap(tester, find.text(_inviteRow));
  await pumpUntil(tester, _code, timeout: const Duration(seconds: 15));
  return tester.widget<Text>(_code).data!;
}

Future<void> _closeInvite(WidgetTester tester) async {
  await tap(tester, find.descendant(of: _sheet, matching: button(_close)));
  must(await _gone(tester, _sheet, const Duration(seconds: 5)), '"닫기" 뒤에도 시트가 남음');
}

/// [finder] 가 [within] 안에 사라지면 true.
Future<bool> _gone(WidgetTester tester, Finder finder, Duration within) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isNotEmpty) {
    if (watch.elapsed > within) return false;
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

/// 설정 → 18a, 세 줄을 받을 때까지.
Future<void> _openHeartTasks(WidgetTester tester) async {
  await _openSettings(tester);
  await tap(tester, find.text(_heartTasksRow));
  await pumpUntil(tester, find.byType(HeartTaskRow), timeout: const Duration(seconds: 15));
}

/// 18a 의 [row] 줄 → 18b. 읽기만 한다(사진 · 제출 안 함).
Future<void> _openSubmit(WidgetTester tester, String row) async {
  await _openHeartTasks(tester);
  await tap(tester, find.text(row));
  await pumpUntil(tester, find.text(_submitTitle), timeout: const Duration(seconds: 10));
  await wait(tester, const Duration(milliseconds: 500));
}

int _count(Finder finder) => finder.evaluate().length;

final Map<String, Area1Case> area2Cases = {
  // 네 글 · 통계(세 칸 또는 전부 0 판) 각 하나, 19 대기 화면 글 0.
  'E-HOME-01': _session((tester, job) async {
    must(!await _homeLoaded(tester), '학교가 열렸는데 19 대기 화면이 보임');
    final words = {for (final text in [..._heroLines, _heroCta, _campusTitle, ..._statLabels, _statEmpty]) text: _inHome(find.text(text))};
    final seen = await _sweep(tester, {...words, 'cohort': find.textContaining(_cohortLead, skipOffstage: false)});
    for (final text in [..._heroLines, _heroCta, _campusTitle]) {
      must(seen[text] == 1, '"$text" ${seen[text]}개');
    }
    final stats = _statLabels.every((label) => seen[label] == 1);
    must(stats != (seen[_statEmpty] == 1), '통계 세 칸 ${[for (final l in _statLabels) seen[l]]} · 전부 0 판 ${seen[_statEmpty]}');
    must(seen['cohort'] == 0, '"$_cohortLead" 가 보임');
    return null;
  }),
  // 화면 세 숫자(쉼표 그대로)를 말한다 — DB · /home/summary 와 맞추기는 PC.
  'E-HOME-02': _session((tester, job) async {
    await _summary(tester);
    final stats = <String, String>{};
    final seen = await _sweep(tester, {'empty': _inHome(find.text(_statEmpty))},
        each: () => stats.addAll({for (final t in tester.widgetList<StatTile>(_inHome(find.byType(StatTile)))) t.label: t.value}));
    must(stats.isNotEmpty || seen['empty'] == 1, '통계 칸도 전부 0 판도 안 보임');
    return seen['empty'] == 1 ? {'empty': true, 'stats': stats} : {'stats': stats};
  }),
  // 칩 순서를 말한다 — DB 순서와 맞추기는 PC.
  'E-HOME-03': _session((tester, job) async {
    await _summary(tester);
    var campuses = <String>[];
    await _sweep(tester, {}, each: () {
      final tags = tester.widgetList<Tag>(_inHome(find.byType(Tag))).map((t) => t.label).toList();
      if (tags.isNotEmpty) campuses = tags;
    });
    must(campuses.isNotEmpty, '"$_campusTitle" 칩이 하나도 없음');
    return {'campuses': campuses};
  }),
  'E-HOME-04': _session(_completion),
  'E-HOME-05': _session(_completion),
  'E-HOME-06': _session(_completion),
  'E-HOME-10': _session((tester, job) async {
    await _summary(tester);
    await tap(tester, _inHome(find.text(_heroCta)));
    await pumpUntil(tester, find.text(_todayTitle), timeout: const Duration(seconds: 10));
    return null;
  }),
  // 하트 글 · 하트 재화 그림 0. 하단 내비 "오늘" 의 하트는 Lucide 선 아이콘이라 재화 그림이 아니다.
  'E-HOME-11': _session((tester, job) async {
    await _summary(tester);
    final currency = _inHome(find.byWidgetPredicate((w) => w is Image && _currencyAsset.hasMatch(_asset(w.image))));
    final seen = await _sweep(tester, {'text': _inHome(find.textContaining('하트')), 'image': currency});
    must(seen['text'] == 0, '"하트" 글 ${seen['text']}개');
    must(seen['image'] == 0, '하트 재화 그림 ${seen['image']}개');
    return null;
  }),
  // 리뷰 띠 목값이 보이면 pass(사용자 결정 10-01 (가) — 심사 때 숨김, 지금은 정상). 레일 그림 경로는 PC 가 본다.
  'E-HOME-12': _session((tester, job) async {
    await _summary(tester);
    // 레일은 맨 위 — 목록을 내리면 안 만들어지므로 내리기 전에 읽는다.
    final rail = tester.widget<MosaicRail>(_inHome(find.byType(MosaicRail))).images;
    final seen = await _sweep(tester, {_reviewRating: _inHome(find.text(_reviewRating)), _reviewCount: _inHome(find.text(_reviewCount))});
    must(seen[_reviewRating] == 1 && seen[_reviewCount] == 1, '리뷰 띠 "$_reviewRating" ${seen[_reviewRating]}개 · "$_reviewCount" ${seen[_reviewCount]}개');
    return {'rail': rail};
  }),
  'E-REF-01': _session((tester, job) async {
    await _openSettings(tester);
    must(_count(find.text(_inviteNote)) == 1, '"$_inviteRow" 줄 부제 "$_inviteNote" 없음');
    final code = await _openInvite(tester);
    must(_count(find.descendant(of: _sheet, matching: find.text(_inviteRow))) == 1, '시트 제목 "$_inviteRow" 없음');
    must(_count(find.descendant(of: _sheet, matching: find.text(_inviteBody))) == 1, '시트 설명 "$_inviteBody" 없음');
    return {'code': code};
  }),
  // 열기 · 닫고 다시 열기. 다시 켬(fresh=false)에서도 같은 둘 — PC 가 모두 DB 코드와 맞춘다.
  'E-REF-02': _session((tester, job) async {
    await _openSettings(tester);
    final codes = <String>[];
    for (var i = 0; i < 2; i++) {
      codes.add(await _openInvite(tester));
      await _closeInvite(tester);
    }
    return {'codes': codes};
  }),
  'E-REF-03': _session((tester, job) async {
    await _openSettings(tester);
    final code = await _openInvite(tester);
    await tap(tester, find.descendant(of: _sheet, matching: find.text(_copy)));
    final toast = find.widgetWithText(AppToast, _copied);
    await pumpUntil(tester, toast, timeout: const Duration(seconds: 3));
    must(_count(toast) == 1, '토스트 "$_copied" ${_count(toast)}개');
    must(_count(find.descendant(of: toast, matching: find.byIcon(AppIcons.check))) == 1, '토스트에 체크 아이콘 없음');
    final clipboard = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    // 3초 토스트 — 2초엔 남아 있고, 그 뒤 3초 안에 사라진다.
    await wait(tester, const Duration(seconds: 2));
    must(toast.evaluate().isNotEmpty, '2초가 안 돼 토스트가 사라짐');
    must(await _gone(tester, toast, const Duration(seconds: 3)), '5초가 지나도 토스트가 남음');
    return {'code': code, 'clipboard': clipboard};
  }),
  // 8개 중 마케팅만 꺼짐. 받기 전에도 화면 기본값이 같아 — 서버 값을 받은 뒤(isLoading 끝 · 오류 없음)에 본다.
  'E-CARD-21': _session((tester, job) async {
    await _openSettings(tester);
    await tap(tester, find.text(_notificationsRow));
    final page = find.byType(NotificationSettingsScreen);
    await pumpUntil(tester, page, timeout: const Duration(seconds: 5));
    final container = ProviderScope.containerOf(tester.element(page));
    final watch = Stopwatch()..start();
    while (container.read(notificationSettingsViewModelProvider).isLoading) {
      must(watch.elapsed < const Duration(seconds: 15), '15초 안에 알림 설정을 못 받음');
      await tester.pump(const Duration(milliseconds: 200));
    }
    final error = container.read(notificationSettingsViewModelProvider).errorMessage;
    must(error == null, '알림 설정을 못 읽음: $error');
    final list = find.descendant(of: page, matching: find.byType(Scrollable)).first;
    final wrong = <String>[];
    for (final MapEntry(key: title, value: on) in _notificationDefaults.entries) {
      final tile = find.descendant(of: page, matching: find.widgetWithText(SwitchListTile, title));
      await tester.scrollUntilVisible(tile, 150, scrollable: list);
      final value = tester.widget<SwitchListTile>(tile).value;
      if (value != on) wrong.add('$title ${value ? '켜짐' : '꺼짐'}');
    }
    must(wrong.isEmpty, '기본값과 다름: $wrong');
    return null;
  }),
  'E-HEART-01': _session((tester, job) async {
    await _openHeartTasks(tester);
    must(_count(find.text(_rewardNotice)) == 1, '위 안내 "$_rewardNotice" 없음');
    final rows = find.byType(HeartTaskRow);
    final order = tester.widgetList<HeartTaskRow>(rows).map((r) => r.task.kind.code).join(',');
    must(order == _taskOrder, '줄 순서 $order');
    for (final (index, texts) in _taskRows.indexed) {
      for (final text in texts) {
        must(_count(find.descendant(of: rows.at(index), matching: find.text(text))) == 1, '${index + 1}번째 줄에 "$text" 없음');
      }
    }
    return null;
  }),
  'E-HEART-02': _session((tester, job) async {
    await _openSubmit(tester, _taskRows[0][0]);
    must(_count(find.text(_submitGuide)) == 1, '안내 "$_submitGuide" ${_count(find.text(_submitGuide))}개');
    must(_count(find.text(_dateHint)) == 1, '"$_dateHint" ${_count(find.text(_dateHint))}개');
    must(!enabled(tester, _submit), '사진 전인데 "$_submit" 이 켜짐');
    return null;
  }),
  'E-HEART-03': _session((tester, job) async {
    await _openSubmit(tester, _taskRows[1][0]);
    must(_count(find.text(_submitGuide)) == 1, '안내 "$_submitGuide" ${_count(find.text(_submitGuide))}개');
    must(_count(find.text(_dateHint)) == 0, '단톡방 18b 에 "$_dateHint" 가 보임');
    return null;
  }),
};
