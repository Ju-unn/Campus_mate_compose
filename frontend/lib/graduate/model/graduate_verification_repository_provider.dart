import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/graduate/model/graduate_verification_repository.dart';
import 'package:campus_mate/graduate/model/http_graduate_verification_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final graduateVerificationRepositoryProvider = Provider<GraduateVerificationRepository>((ref) {
  return HttpGraduateVerificationRepository(ref.read(apiClientProvider));
});
