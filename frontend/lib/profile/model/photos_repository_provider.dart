import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/model/http_photos_repository.dart';
import 'package:campus_mate/profile/model/photos_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final photosRepositoryProvider = Provider<PhotosRepository>((ref) {
  return HttpPhotosRepository(ref.read(apiClientProvider));
});
