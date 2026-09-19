import 'package:campus_mate/auth/model/http_student_verification_repository.dart';
import 'package:campus_mate/auth/model/student_verification_repository.dart';
import 'package:campus_mate/core/env.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// FastAPI 기본 URL은 `Env.apiBaseUrl`(`--dart-define=API_BASE_URL=...`)에서 읽는다.
final studentVerificationRepositoryProvider = Provider<StudentVerificationRepository>((ref) {
  return HttpStudentVerificationRepository(Env.apiBaseUrl, http.Client(), Supabase.instance.client.auth);
});
