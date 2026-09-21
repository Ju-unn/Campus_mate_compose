import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/model/avatar_repository.dart';
import 'package:campus_mate/profile/model/http_avatar_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final avatarRepositoryProvider = Provider<AvatarRepository>((ref) {
  return HttpAvatarRepository(ref.read(apiClientProvider));
});
