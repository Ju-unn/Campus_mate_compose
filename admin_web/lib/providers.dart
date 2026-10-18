import 'package:campus_mate_admin/api/admin_api.dart';
import 'package:campus_mate_admin/auth/admin_auth.dart';
import 'package:campus_mate_admin/auth/supabase_admin_auth.dart';
import 'package:campus_mate_admin/config/admin_config.dart';
import 'package:campus_mate_admin/platform/page_reload.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// 시험은 모두 갈아 끼운다(test/helpers/fakes.dart).

/// 설정 누락 화면의 "다시 불러오기" — 브라우저 페이지를 다시 연다.
final pageReloaderProvider = Provider<void Function()>((ref) => reloadPage);

final adminConfigProvider = Provider<AdminConfig>((ref) => const AdminConfig.fromEnvironment());

/// Supabase 가 초기화된 뒤(설정이 갖춰졌을 때)에만 읽힌다 — 관문이 설정부터 본다.
final adminAuthProvider = Provider<AdminAuth>((ref) {
  final auth = SupabaseAdminAuth(Supabase.instance.client.auth);
  ref.onDispose(auth.dispose);
  return auth;
});

final adminApiProvider = Provider<AdminApi>((ref) {
  final auth = ref.watch(adminAuthProvider);
  final client = http.Client();
  ref.onDispose(client.close);
  return AdminApi(ref.watch(adminConfigProvider).apiBaseUrl, client, () => auth.accessToken);
});
