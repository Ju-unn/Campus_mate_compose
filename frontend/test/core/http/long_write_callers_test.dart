import 'dart:async';

import 'package:campus_mate/common/failure.dart';
import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/http/http_send.dart';
import 'package:campus_mate/me/model/repository/http_me_repository.dart';
import 'package:campus_mate/profile/appearance/model/repository/http_appearance_type_repository.dart';
import 'package:campus_mate/profile/avatar/model/repository/http_avatar_repository.dart';
import 'package:campus_mate/profile/basic/model/data/basic_info_submission.dart';
import 'package:campus_mate/profile/basic/model/repository/http_basic_info_repository.dart';
import 'package:campus_mate/profile/bio/model/repository/http_bio_repository.dart';
import 'package:campus_mate/profile/ideal/model/data/ideal_conditions_submission.dart';
import 'package:campus_mate/profile/ideal/model/repository/http_ideal_conditions_repository.dart';
import 'package:campus_mate/profile/ideal/model/repository/http_ideal_note_repository.dart';
import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';
import 'package:campus_mate/profile/traits/model/repository/http_survey_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

/// 서버가 외부 AI 를 기다리는 쓰기는 기본 상한(30초)이 아니라 긴 상한(90초)을 넘긴다 — 기본 상한에 끊으면 서버는 저장을
/// 마쳤는데 화면만 실패로 보인다. 자기소개 초안은 OpenAI 답을, 프로필 저장은 저장 뒤 매칭 벡터(임베딩 · 글 정리)를 기다린다
/// (backend profile_onboarding/router.py `_refresh_vectors` · me/router.py). 사진 올리기(multipart)는 http_send_test 가 본다.
void main() {
  const basicInfo = BasicInfoSubmission(
    nickname: 'nick',
    birthYear: 2002,
    heightCm: 175,
    phoneNumber: '01001352468',
    gender: 'male',
  );
  const idealConditions = IdealConditionsSubmission(preferredAgeMin: 22, preferredAgeMax: 27, acceptsSmoker: null);

  final longWrites = <String, Future<Result<Object?>> Function(ApiClient api)>{
    'POST /profile-onboarding/avatar/generate': (api) => HttpAvatarRepository(api).generateAvatar(),
    'POST /me/avatar/regenerate': (api) => HttpAvatarRepository(api).regenerateAvatar(),
    'POST /profile-onboarding/bio-draft': (api) => HttpBioRepository(api).generateDraft(),
    'POST /profile-onboarding/bio': (api) => HttpBioRepository(api).submit('bio'),
    'POST /profile-onboarding/ideal-note': (api) => HttpIdealNoteRepository(api).submit('note'),
    'POST /profile-onboarding/basic-info': (api) => HttpBasicInfoRepository(api).submit(basicInfo),
    'POST /profile-onboarding/appearance-type': (api) =>
        HttpAppearanceTypeRepository(api).submit(AnimalType.cat, ImpressionType.kind),
    'POST /profile-onboarding/survey': (api) => HttpSurveyRepository(api).submit(const {}, Religion.none, false),
    'POST /profile-onboarding/ideal-conditions': (api) => HttpIdealConditionsRepository(api).submit(idealConditions),
    'PATCH /me/profile': (api) => HttpMeRepository(api).updateProfile(bio: 'bio'),
  };

  for (final MapEntry(key: endpoint, value: call) in longWrites.entries) {
    testWidgets('$endpoint 는 90초까지 기다린 뒤 NetworkFailure 로 끝난다', (tester) async {
      final auth = MockGoTrueClient();
      final session = MockSession();
      when(() => session.accessToken).thenReturn('token-abc');
      when(() => auth.currentSession).thenReturn(session);
      final sent = <String>[];
      final client = MockClient((request) {
        sent.add('${request.method} ${request.url.path}');
        return Completer<http.Response>().future;
      });
      Object? outcome;
      unawaited(call(ApiClient('https://api.test', client, auth))
          .then((result) => outcome = result.when(onSuccess: (_) => 'success', onFailure: (f) => f)));

      await tester.pump(longWriteTimeout - const Duration(milliseconds: 1));
      expect(outcome, isNull, reason: '쓰기 기본 상한(30초)에 끊기면 안 된다');
      expect(sent, [endpoint]);

      await tester.pump(const Duration(milliseconds: 1));
      expect(outcome, isA<NetworkFailure>());
    });
  }
}
