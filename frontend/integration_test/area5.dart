import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:campus_mate/account/view/withdraw_sheets.dart';
import 'package:campus_mate/chat/view/chat_input_bar.dart';
import 'package:campus_mate/chat/view/chat_list_row.dart';
import 'package:campus_mate/chat/view/chat_room_screen.dart';
import 'package:campus_mate/chat/view/message_bubble.dart';
import 'package:campus_mate/chat/view/trust_reveal_bubble.dart';
import 'package:campus_mate/common/widgets/app_bottom_nav.dart';
import 'package:campus_mate/common/widgets/app_button.dart';
import 'package:campus_mate/common/widgets/app_toast.dart';
import 'package:campus_mate/common/widgets/photo_slider.dart';
import 'package:campus_mate/common/widgets/school_label.dart';
import 'package:campus_mate/common/widgets/select_chip.dart';
import 'package:campus_mate/core/auth/account_status_listenable.dart';
import 'package:campus_mate/core/env.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/core/theme/app_colors.dart';
import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/core/theme/app_typography.dart';
import 'package:campus_mate/friend_review/view/friend_review_card.dart';
import 'package:campus_mate/friend_review/view/received_reviews_screen.dart';
import 'package:campus_mate/friend_review/view/written_reviews_screen.dart';
import 'package:campus_mate/matching/view/acceptance_row.dart';
import 'package:campus_mate/matching/view/card_detail_screen.dart';
import 'package:campus_mate/matching/view/conversations_screen.dart';
import 'package:campus_mate/matching/view/daily_card_summary.dart';
import 'package:campus_mate/me/view/basic_info_edit_screen.dart';
import 'package:campus_mate/me/view/me_load_error.dart';
import 'package:campus_mate/me/view/my_photos_screen.dart';
import 'package:campus_mate/me/view/my_profile_screen.dart';
import 'package:campus_mate/me/view/profile_edit_screen.dart';
import 'package:campus_mate/me/view/profile_entry_row.dart';
import 'package:campus_mate/me/view/profile_hero.dart';
import 'package:campus_mate/me/view/profile_manage_screen.dart';
import 'package:campus_mate/me/viewmodel/my_photos_view_model.dart';
import 'package:campus_mate/me/viewmodel/my_profile_provider.dart';
import 'package:campus_mate/profile/view/appearance_pickers.dart';
import 'package:campus_mate/profile/view/ideal_conditions_screen.dart';
import 'package:campus_mate/profile/view/photo_tiles.dart';
import 'package:campus_mate/profile/view/tag_picker_screen.dart';
import 'package:campus_mate/profile/viewmodel/avatar_generation_view_model.dart';
import 'package:campus_mate/main.dart' as app;
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'area1.dart';
import 'support.dart';

part 'area5_act.dart';
part 'area5_edge.dart';
part 'area5_fake.dart';
part 'area5_kill.dart';
part 'area5_more.dart';
part 'area5_new.dart';
part 'area5_photo.dart';
part 'area5_read.dart';
part 'area5_time.dart';
part 'area5_two.dart';
part 'area5_wd.dart';

/// 영역 5 폰 A 한 대 — 나 탭 · 탈퇴 · 경계. PC 쪽은 e2e/area5_*.py 의 같은 번호(계정 · DB 를 준비하고 앱이 말한 값을 판정한다).
/// 앱은 화면을 열어 읽거나 누르고 본 것을 Map 으로 돌려준다. 화면 글자 · 위젯은 시나리오가 아니라 지금 화면 코드
/// (frontend/lib/me · account · matching/view/settings_screen · profile/view)에서 옮겼다.
/// 탈퇴를 실제로 누르는 가설은 area5_wd.dart 의 넷(E-WD-04 · 16 · 18 · E-EDGE-20)뿐이다 — 이 파일 · area5_read · area5_act 는 "정말 영구 삭제" 를 누르지 않는다.
final Map<String, Area1Case> area5Cases = {...area5CasesRead, ...area5CasesAct, ...area5CasesPhoto, ...area5CasesWd, ...area5CasesTime, ...area5CasesTwo, ...area5CasesEdge, ...area5CasesFake, ...area5CasesKill, ...area5CasesMore, ...area5CasesNew};

const _manageEntry = '프로필 편집'; // my_profile_screen.dart 입구 줄(profile_entry_row.dart — InkWell 이 행 전체를 감싼다)
const _previewEntry = '남이 보는 내 프로필 카드';
const _regenPill = '다시 만들기 · 10'; // profile_hero.dart `_RegeneratePill`
const _heartLine = '지금 보유한 하트는'; // avatar_regen_sheet.dart 보유 하트 줄(무료 시트에는 없다)
const _cancel = '취소';
const _editLink = '수정 ›'; // profile_manage_screen.dart 기본 정보 "수정 ›"
const _withdraw = '탈퇴하기'; // settings_screen.dart AppButton · account_suspended_screen.dart 글자 버튼
const _firstTitle = '정말 떠나시나요?'; // withdraw_sheets.dart 1차 시트
const _deleteLead = '탈퇴하면 아래 내용이 삭제돼요';
const _deleteWarning = '삭제한 내용은 되돌릴 수 없고, 재가입은 2개월 뒤에 가능해요.';
const _deleteForever = '영구 삭제'; // 1차 시트 버튼 — 누르면 최종 시트가 뜬다(탈퇴는 아니다)
const _finalTitle = '정말 삭제할까요?'; // 최종 시트
const _deletedItems = ['프로필과 인증 정보', '수락 매칭 기록', '모든 대화 내용'];
const _suspendedSheetTitle = '정지 중에 탈퇴할까요?'; // 14f-1
const _suspendedWarning = '정지 중에 탈퇴하면 다시 가입할 수 없어요';
const _sectionTitles = ['실제 사진', '기본 정보', '선호 조건', '자기소개']; // profile_manage_screen.dart `_SectionHeader`
const _bioEntry = '자기소개 · 태그';
const _agePref = '선호 나이 범위';
const _heightPref = '선호 키 범위';
const _replacePhotos = '실제 사진 교체';
const _ageIgnore = '나이는 상관없어요'; // ideal_conditions_screen.dart 체크 줄

bool _has(Finder finder) => finder.evaluate().isNotEmpty;

/// 앞 가설의 세션을 지우고 일감의 토큰으로 로그인한 뒤 [body] 를 돈다(area1.dart 와 같다 — 그쪽 것은 라이브러리 밖에서 못 쓴다).
Area1Case _session(Area1Case body) => (tester, job) async {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      if (job['token_hash'] case final String hash) await signIn(hash);
      return body(tester, job);
    };

Finder _tab(String label) => find.descendant(of: find.byType(AppBottomNav), matching: find.text(label));

/// 나 탭 입구 줄의 제목 글자 — 줄 가운데가 아니라 안의 글자를 누른다(줄 전체 폭 위젯의 가운데는 빈 자리일 수 있다).
Finder _entry(String title) => find.descendant(of: find.byType(ProfileEntryRow), matching: find.text(title));

/// 맨 위 화면의 앱바 글자(없으면 null) — 화면이 어디인지 말할 때 쓴다.
String? _title(WidgetTester tester) {
  final bars = find.byType(AppBar);
  if (!_has(bars)) return null;
  final title = tester.widget<AppBar>(bars.last).title;
  return title is Text ? title.data : null;
}

/// 홈 → 아래 탭 "나" → 히어로가 그려질 때까지.
Future<void> _openMe(WidgetTester tester) async {
  await arrive(tester, 'home');
  await tap(tester, _tab('나'));
  await pumpUntil(tester, find.byType(ProfileHero));
}

/// 앱바 뒤로 — 편집 화면(EditAppBar)은 화살표 아이콘, 설정은 기본 BackButton. 닫히는 움직임이 끝나기를 기다린다.
Future<void> _back(WidgetTester tester) async {
  final edit = find.byIcon(AppIcons.arrowLeft);
  await tap(tester, _has(edit) ? edit : find.byType(BackButton));
  await wait(tester, const Duration(milliseconds: 800));
}

/// 지금 화면 제목이 [title] 이 아니면 앱바 뒤로로 거슬러 간다(시스템 뒤로가 안 먹은 경우에도 다음 화면을 볼 수 있게).
Future<void> _returnTo(WidgetTester tester, String title) async {
  for (var tries = 0; tries < 4 && _title(tester) != title; tries++) {
    if (!_has(find.byIcon(AppIcons.arrowLeft)) && !_has(find.byType(BackButton))) return;
    await _back(tester);
  }
}

/// 15 → "프로필 편집" 입구 → 15-5(첫 섹션 제목이 그려질 때까지).
Future<void> _openManage(WidgetTester tester) async {
  await _openMe(tester);
  await tap(tester, _entry(_manageEntry));
  await pumpUntil(tester, find.text(_sectionTitles.first));
  await wait(tester, const Duration(milliseconds: 500)); // 사진 · 줄이 자리를 잡게
}

Finder get _manageScrollable =>
    find.descendant(of: find.byType(ProfileManageScreen), matching: find.byType(Scrollable)).first;

/// 15-5 목록을 맨 위로 되돌린 뒤 [finder] 가 눌릴 수 있을 때까지 내린다(목록은 보이는 줄만 만든다).
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  tester.state<ScrollableState>(_manageScrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(finder, 300, scrollable: _manageScrollable);
}

/// 15 → 톱니 → 설정(16).
Future<void> _openSettings(WidgetTester tester) async {
  await tap(tester, find.byIcon(AppIcons.settings));
  await arrive(tester, 'settings');
  await wait(tester, const Duration(milliseconds: 500));
}

/// 설정의 "탈퇴하기" AppButton 을 눌러 1차 시트(16c)까지 — 설정은 나 탭 위에 쌓이므로 설정 화면의 목록을 굴린다.
Future<void> _openWithdrawSheet(WidgetTester tester) async {
  final settings = find.ancestor(of: screen('settings'), matching: find.byType(Scaffold)).first;
  final withdraw = button(_withdraw);
  await tester.scrollUntilVisible(withdraw, 300, scrollable: find.descendant(of: settings, matching: find.byType(Scrollable)).first);
  await tap(tester, withdraw);
  await pumpUntil(tester, find.text(_firstTitle));
}

/// 1차 시트의 "영구 삭제" → 최종 시트("정말 삭제할까요?")까지. 최종 시트의 "정말 영구 삭제" 는 누르지 않는다.
Future<void> _openFinalSheet(WidgetTester tester) async {
  await tap(tester, button(_deleteForever));
  await pumpUntil(tester, find.text(_finalTitle));
  await wait(tester, const Duration(milliseconds: 500)); // 1차 시트가 물러나는 움직임
}

List<String> _buttonLabels(WidgetTester tester, Finder within) =>
    [for (final b in tester.widgetList<AppButton>(find.descendant(of: within, matching: find.byType(AppButton)))) b.label];

/// 열려 있는 묻는 창(대화상자 · 바텀시트) — 시스템 뒤로 뒤에 0 이어야 한다.
bool _asking() => _has(find.byType(Dialog)) || _has(find.byType(BottomSheet));
