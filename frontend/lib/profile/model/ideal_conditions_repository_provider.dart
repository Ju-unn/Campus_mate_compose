import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/model/http_ideal_conditions_repository.dart';
import 'package:campus_mate/profile/model/ideal_conditions_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final idealConditionsRepositoryProvider = Provider<IdealConditionsRepository>((ref) {
  return HttpIdealConditionsRepository(ref.read(apiClientProvider));
});
