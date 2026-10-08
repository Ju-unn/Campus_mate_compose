import 'dart:async';

import 'package:campus_mate/auth/model/school_email_repository.dart';
import 'package:campus_mate/auth/model/supabase_school_email_repository.dart';
import 'package:campus_mate/auth/model/temporary_auth_connection.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 임시 연결을 만드는 자리. url · 익명키는 `Supabase.initialize` 와 같은 자리(`SupabaseConfig.fromEnvironment`)에서 읽는다.
/// 시험은 덮어써 네트워크 없이 돌린다.
final temporaryAuthFactoryProvider = Provider<GoTrueClient Function()>((ref) {
  return SupabaseConfig.fromEnvironment().openTemporaryAuth;
});

/// 02 에서 보낸 임시 연결로 03 에서 확인해야 하므로 앱 전체가 한 벌을 쓴다(autoDispose 아님).
/// 로그아웃하면 SessionScope 가 ProviderScope 를 새로 만든다 — 그때 임시 연결도 비운다.
final schoolEmailRepositoryProvider = Provider<SchoolEmailRepository>((ref) {
  final connection = TemporaryAuthConnection(ref.read(temporaryAuthFactoryProvider));
  ref.onDispose(() => unawaited(connection.close()));
  return SupabaseSchoolEmailRepository(ref.read(apiClientProvider), connection);
});
