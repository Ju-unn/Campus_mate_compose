import 'package:campus_mate/auth/model/school_email_repository.dart';
import 'package:campus_mate/auth/model/supabase_school_email_repository.dart';
import 'package:campus_mate/auth/model/temporary_auth_connection.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/core/supabase/supabase_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 02 에서 보낸 임시 연결로 03 에서 확인해야 하므로 앱 전체가 한 벌을 쓴다(autoDispose 아님).
/// 임시 연결의 url · 익명키는 `Supabase.initialize` 와 같은 자리(`SupabaseConfig.fromEnvironment`)에서 읽는다.
final schoolEmailRepositoryProvider = Provider<SchoolEmailRepository>((ref) {
  return SupabaseSchoolEmailRepository(
    ref.read(apiClientProvider),
    TemporaryAuthConnection(SupabaseConfig.fromEnvironment().openTemporaryAuth),
  );
});
