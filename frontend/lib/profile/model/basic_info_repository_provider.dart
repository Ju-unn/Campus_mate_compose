import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/model/basic_info_repository.dart';
import 'package:campus_mate/profile/model/http_basic_info_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final basicInfoRepositoryProvider = Provider<BasicInfoRepository>((ref) {
  return HttpBasicInfoRepository(ref.read(apiClientProvider));
});
