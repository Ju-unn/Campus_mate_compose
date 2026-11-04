import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/basic/model/repository/acquisition_repository.dart';
import 'package:campus_mate/profile/basic/model/repository/http_acquisition_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final acquisitionRepositoryProvider = Provider<AcquisitionRepository>((ref) {
  return HttpAcquisitionRepository(ref.read(apiClientProvider));
});
