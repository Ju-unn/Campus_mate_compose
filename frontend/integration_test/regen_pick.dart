import 'dart:io';

import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:campus_mate/me/view/avatar_regen_pick_screen.dart';
import 'package:campus_mate/me/viewmodel/avatar_regen_pick_view_model.dart';
import 'package:campus_mate/profile/view/avatar_source_tile.dart';
import 'package:campus_mate/safety/view/safety_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

import 'area1.dart' show appears, button, must, tap, wait;
import 'support.dart';

// 아바타 다시 만들기가 사진부터 고르게 된 뒤(15b-4 → 15b-5 → 15b 시트, 앱 `AvatarRegenPickScreen`)의 기기 시나리오 공용 걸음.
// 나 탭 알약 → 사진 고르기 → (갤러리 훅에 PC 가 앱 캐시에 넣어 둔 사진) → 칸 → "이 사진으로 아바타 만들기" → 하트 확인 시트가 뜰 때까지.
// 시트의 만들기 · 충전 · 취소를 누르는 일은 부른 가설이 한다. PC 쪽은 `e2e/area1_b3.py` 의 `regen_photo` 가 사진을 앱 캐시로 옮긴다.

/// PC 가 앱 캐시(`e2e-photos/`)에 넣어 두는 다시 만들기용 사진 — 얼굴이 보여야 기기 안 얼굴 검사를 지난다(사진 세트의 face1.jpg).
const regenPhotoName = 'face1.jpg';

/// 15b-5 의 버튼 글자(가입 04-3 과 같다).
const regenPickCta = '이 사진으로 아바타 만들기';

/// 사진 고르기 화면이 뜰 때까지 · 얼굴 검사가 끝나 사진이 칸에 들어갈 때까지 기다리는 시간.
const _regenScreenWait = Duration(seconds: 20);
const _regenCheckWait = Duration(seconds: 45);

Future<File> _regenPhoto() async {
  final file = File('${(await getTemporaryDirectory()).path}/e2e-photos/$regenPhotoName');
  if (!file.existsSync()) throw E2eBlocked('사진 세트 파일 없음: $regenPhotoName (PC 의 regen_photo 가 앱 캐시로 옮겨야 한다)');
  return file;
}

/// 나 탭(15)에서 [pill] 알약을 눌러 하트 확인 시트가 뜰 때까지 간다. 사진이 얼굴 검사를 못 지나면 E2eBlocked.
Future<void> e2eRegenToSheet(WidgetTester tester, String pill) async {
  final photo = await _regenPhoto(); // 알약을 누르기 전에 — 파일이 없으면 화면을 건드리지 않고 막힌다
  await tap(tester, find.text(pill));
  await pumpUntil(tester, find.byType(AvatarRegenPickScreen), timeout: _regenScreenWait);
  final container = ProviderScope.containerOf(tester.element(find.byType(AvatarRegenPickScreen)));
  container.read(avatarRegenPickViewModelProvider.notifier).pickFromGallery = () async => photo;
  await tap(tester, find.byIcon(AppIcons.plus)); // 빈 "사진 추가" 칸의 + 아이콘(다른 + 는 이 화면에 없다)
  final picked = await appears(tester, find.byType(AvatarSourceTile), _regenCheckWait);
  if (picked == null) {
    throw E2eBlocked('다시 만들기 사진이 기기 얼굴 검사에서 빠짐($regenPhotoName) — 사진 세트 확인');
  }
  must(button(regenPickCta).evaluate().isNotEmpty, '"$regenPickCta" 버튼이 없음');
  await tap(tester, find.descendant(of: button(regenPickCta), matching: find.text(regenPickCta)));
  await pumpUntil(tester, find.byType(SafetySheet), timeout: const Duration(seconds: 10));
  await wait(tester, const Duration(milliseconds: 500)); // 시트가 올라오는 움직임
}
