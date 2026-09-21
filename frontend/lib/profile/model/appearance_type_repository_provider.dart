import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/model/appearance_type_repository.dart';
import 'package:campus_mate/profile/model/http_appearance_type_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appearanceTypeRepositoryProvider = Provider<AppearanceTypeRepository>((ref) {
  return HttpAppearanceTypeRepository(ref.read(apiClientProvider));
});
