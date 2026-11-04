import 'dart:convert';

import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/profile/ideal/model/data/ideal_conditions_submission.dart';
import 'package:campus_mate/profile/ideal/model/repository/http_ideal_conditions_repository.dart';
import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

/// 서버 계약(앱 1.0.2): POST /profile-onboarding/ideal-conditions 본문에 `accepts_smoker`(bool)를 늘 싣는다.
/// 온보딩 저장과 나 탭 수정 저장이 같은 길이라 이 저장소 하나로 둘 다 덮는다.
void main() {
  late List<http.Request> requests;
  late HttpIdealConditionsRepository repository;

  setUp(() {
    final auth = MockGoTrueClient();
    final session = MockSession();
    when(() => session.accessToken).thenReturn('token-abc');
    when(() => auth.currentSession).thenReturn(session);
    requests = [];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode({'ok': true}), 200, headers: {'content-type': 'application/json'});
    });
    repository = HttpIdealConditionsRepository(ApiClient('https://api.test', client, auth));
  });

  IdealConditionsSubmission submission({required bool? acceptsSmoker}) => IdealConditionsSubmission(
        preferredAgeMin: 22,
        preferredAgeMax: 27,
        preferredAnimalTypes: const [AnimalType.cat],
        preferredImpressionTypes: const [ImpressionType.kind],
        acceptsSmoker: acceptsSmoker,
      );

  Map<String, dynamic> sentBody() => jsonDecode(requests.single.body) as Map<String, dynamic>;

  test('"싫어요"(false)는 accepts_smoker: false 로 실어 보낸다', () async {
    await repository.submit(submission(acceptsSmoker: false));

    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/profile-onboarding/ideal-conditions');
    expect(sentBody()['accepts_smoker'], isFalse);
  });

  test('"상관없어요"(true)는 accepts_smoker: true 로 실어 보낸다', () async {
    await repository.submit(submission(acceptsSmoker: true));

    expect(sentBody().containsKey('accepts_smoker'), isTrue);
    expect(sentBody()['accepts_smoker'], isTrue);
  });

  // 아직 안 고른(null) 사람 — null 을 보내면 서버가 DB 값을 null 로 되돌린다. 서버는 키가 없을 때만 DB 값을 그대로 둔다.
  test('안 고른 채(null)면 accepts_smoker 키를 아예 싣지 않는다', () async {
    await repository.submit(submission(acceptsSmoker: null));

    expect(sentBody().containsKey('accepts_smoker'), isFalse);
    expect(sentBody()['preferred_age_min'], 22); // 나머지 칸은 그대로 간다
  });
}
