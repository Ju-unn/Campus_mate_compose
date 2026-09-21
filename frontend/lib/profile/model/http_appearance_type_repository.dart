import 'dart:convert';

import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:campus_mate/profile/model/appearance_type_repository.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// [AppearanceTypeRepository]를 FastAPI 호출로 구현한다.
class HttpAppearanceTypeRepository implements AppearanceTypeRepository {
  const HttpAppearanceTypeRepository(this._baseUrl, this._client, this._auth);

  final String _baseUrl;
  final http.Client _client;
  final GoTrueClient _auth;

  @override
  Future<Result<void>> submit(AnimalType animalType, ImpressionType impressionType) async {
    final result = await sendAuthorizedRequest(
      _client,
      _auth,
      (accessToken) => http.Request('POST', Uri.parse('$_baseUrl/profile-onboarding/appearance-type'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'animal_type': animalType.name, 'impression_type': impressionType.name}),
    );
    return result.when(
      onSuccess: (_) => const Success(null),
      onFailure: (failure) => FailureResult(failure),
    );
  }
}
