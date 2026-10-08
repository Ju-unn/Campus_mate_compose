import 'package:campus_mate/auth/model/school_email_repository_provider.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/core/http/api_client.dart';
import 'package:campus_mate/core/http/api_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  setUpAll(() => registerFallbackValue(SignOutScope.local));

  // 로그아웃하면 SessionScope 가 ProviderScope 를 새로 만든다 — 그때 임시 연결도 비워야 한다(지시문 13 A-5).
  test('provider 가 버려지면(로그아웃) 임시 연결을 이 기기에서만 로그아웃해 비운다', () async {
    final temporary = MockGoTrueClient();
    when(() => temporary.signInWithOtp(email: any(named: 'email'), shouldCreateUser: any(named: 'shouldCreateUser')))
        .thenAnswer((_) async {});
    when(() => temporary.signOut(scope: any(named: 'scope'))).thenAnswer((_) async {});
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient('https://api.test', MockClient((_) async => http.Response('{}', 200)), MockGoTrueClient()),
        ),
        temporaryAuthFactoryProvider.overrideWithValue(() => temporary),
      ],
    );
    await container.read(schoolEmailRepositoryProvider).requestCode(UniversityEmail.tryParse('hong@snu.ac.kr')!);

    container.dispose();
    await pumpEventQueue();

    verify(() => temporary.signOut(scope: SignOutScope.local)).called(1);
  });
}
