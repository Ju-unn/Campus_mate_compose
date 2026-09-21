import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/model/bio_repository.dart';
import 'package:campus_mate/profile/model/http_bio_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bioRepositoryProvider = Provider<BioRepository>((ref) {
  return HttpBioRepository(ref.read(apiClientProvider));
});
