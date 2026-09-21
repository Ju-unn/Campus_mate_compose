import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:campus_mate/profile/model/http_ideal_note_repository.dart';
import 'package:campus_mate/profile/model/ideal_note_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final idealNoteRepositoryProvider = Provider<IdealNoteRepository>((ref) {
  return HttpIdealNoteRepository(ref.read(apiClientProvider));
});
