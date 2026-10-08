import 'dart:io';

import 'package:campus_mate/core/draft/draft_store.dart';
import 'package:campus_mate/core/draft/shared_preferences_draft_store.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱을 켤 때 온보딩 임시 저장소를 연다(디스크를 한 번 읽어 둔다 — 뷰모델이 처음 상태를 바로 읽게).
///
/// 디스크나 앱 임시 폴더를 열지 못해도 **앱은 그대로 뜬다** — 임시 저장 없이([NoDraftStore]) 예전처럼 메모리에만 든다.
/// 로그에는 못 연 사실과 예외 종류만 남긴다. 예외 문구에는 경로 같은 값이 들어 있을 수 있어 남기지 않는다.
/// [preferences] · [temporaryDirectory] 는 시험이 실패를 흉내 내려고 갈아끼운다.
Future<DraftStore> openDraftStore({
  required String? Function() accountId,
  Future<SharedPreferences> Function() preferences = SharedPreferences.getInstance,
  Future<Directory> Function() temporaryDirectory = getTemporaryDirectory,
}) async {
  try {
    final opened = await preferences();
    final temporary = await temporaryDirectory();
    return SharedPreferencesDraftStore(opened, accountId: accountId, fileDirectory: temporary.path);
  } on Object catch (error) {
    debugPrint('온보딩 임시 저장소를 열지 못해 임시 저장 없이 시작한다 (${error.runtimeType})');
    return const NoDraftStore();
  }
}
