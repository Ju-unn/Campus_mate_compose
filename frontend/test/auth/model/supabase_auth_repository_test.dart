import 'package:campus_mate/auth/model/supabase_auth_repository.dart';
import 'package:campus_mate/auth/model/university_email.dart';
import 'package:campus_mate/auth/model/verification_code.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late MockGoTrueClient auth;
  late SupabaseAuthRepository repository;
  final email = UniversityEmail.tryParse('hong@snu.ac.kr')!;

  setUp(() {
    auth = MockGoTrueClient();
    repository = SupabaseAuthRepository(auth);
  });

  test('요청이 성공하면 Success 를 돌려준다', () async {
    when(() => auth.signInWithOtp(email: any(named: 'email'))).thenAnswer((_) async {});

    final result = await repository.requestOtp(email);

    expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
    verify(() => auth.signInWithOtp(email: 'hong@snu.ac.kr')).called(1);
  });

  test('429 응답이면 RateLimitedFailure', () async {
    when(() => auth.signInWithOtp(email: any(named: 'email')))
        .thenThrow(const AuthException('rate limit', statusCode: '429'));

    final result = await repository.requestOtp(email);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<RateLimitedFailure>());
  });

  test('Auth Hook이 거부하면 SignUpRejectedFailure 에 서버 메시지를 담는다', () async {
    when(() => auth.signInWithOtp(email: any(named: 'email')))
        .thenThrow(const AuthException('허용되지 않은 학교 이메일이에요', statusCode: '422'));

    final result = await repository.requestOtp(email);

    final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
    expect(failure, isA<SignUpRejectedFailure>());
    expect(failure!.toDisplayMessage(), '허용되지 않은 학교 이메일이에요');
  });

  test('검증에 성공하면 Success', () async {
    final code = VerificationCode.tryParse('123456')!;
    when(
      () => auth.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: OtpType.email),
    ).thenAnswer((_) async => AuthResponse());

    final result = await repository.verifyOtp(email, code);

    expect(result.when(onSuccess: (_) => true, onFailure: (_) => false), isTrue);
  });

  test('기한이 지난 코드면 WrongCodeFailure', () async {
    final code = VerificationCode.tryParse('000000')!;
    when(
      () => auth.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: OtpType.email),
    ).thenThrow(
      const AuthException('Token has expired or is invalid', statusCode: '403', code: 'otp_expired'),
    );

    final result = await repository.verifyOtp(email, code);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<WrongCodeFailure>());
  });

  test('틀린 코드면 WrongCodeFailure', () async {
    final code = VerificationCode.tryParse('000000')!;
    when(
      () => auth.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: OtpType.email),
    ).thenThrow(
      const AuthException('Invalid login credentials', statusCode: '403', code: 'invalid_credentials'),
    );

    final result = await repository.verifyOtp(email, code);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<WrongCodeFailure>());
  });

  test('코드 값이 없는 403 은 예전처럼 코드 문제로 본다', () async {
    final code = VerificationCode.tryParse('000000')!;
    when(
      () => auth.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: OtpType.email),
    ).thenThrow(const AuthException('Token has expired or is invalid', statusCode: '403'));

    final result = await repository.verifyOtp(email, code);

    expect(result.when(onSuccess: (_) => null, onFailure: (f) => f), isA<WrongCodeFailure>());
  });

  test('정지된 계정의 403 은 코드 탓으로 돌리지 않는다', () async {
    // "코드가 맞지 않아요" 로 보이면 사용자가 멀쩡한 코드를 계속 다시 넣는다.
    final code = VerificationCode.tryParse('123456')!;
    when(
      () => auth.verifyOTP(email: any(named: 'email'), token: any(named: 'token'), type: OtpType.email),
    ).thenThrow(const AuthException('User is banned', statusCode: '403', code: 'user_banned'));

    final result = await repository.verifyOtp(email, code);

    final failure = result.when(onSuccess: (_) => null, onFailure: (f) => f);
    expect(failure, isNot(isA<WrongCodeFailure>()));
    expect(failure, isA<UnknownFailure>());
  });
}
