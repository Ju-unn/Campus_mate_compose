import 'package:campus_mate/consent/model/consent_repository.dart';
import 'package:campus_mate/consent/model/http_consent_repository.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final consentRepositoryProvider = Provider<ConsentRepository>((ref) {
  return HttpConsentRepository(ref.read(apiClientProvider));
});
