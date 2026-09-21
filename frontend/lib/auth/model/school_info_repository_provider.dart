import 'package:campus_mate/auth/model/http_school_info_repository.dart';
import 'package:campus_mate/auth/model/school_info_repository.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// FastAPI 기본 URL은 `Env.apiBaseUrl`(`--dart-define=API_BASE_URL=...`)에서 읽는다.
final schoolInfoRepositoryProvider = Provider<SchoolInfoRepository>((ref) {
  return HttpSchoolInfoRepository(ref.read(apiClientProvider));
});
