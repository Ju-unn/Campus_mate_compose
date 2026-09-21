import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/model/http_tag_picker_repository.dart';
import 'package:campus_mate/profile/model/tag_picker_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final tagPickerRepositoryProvider = Provider<TagPickerRepository>((ref) {
  return HttpTagPickerRepository(ref.read(apiClientProvider));
});
