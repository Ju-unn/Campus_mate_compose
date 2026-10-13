import 'package:campus_mate/account/model/apple_withdrawal_code.dart';
import 'package:campus_mate/auth/model/apple_login_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show AuthorizationErrorCode, SignInWithAppleAuthorizationException, SignInWithAppleNotSupportedException;
import 'package:supabase_flutter/supabase_flutter.dart';

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockUser extends Mock implements User {}

/// 실제 애플 창 대신 쓰는 가짜. 몇 번 띄웠는지 센다.
class _FakeAppleClient implements AppleLoginClient {
  int codeRequests = 0;
  Object? error;

  @override
  Future<String?> requestIdToken(String hashedNonce) => throw UnimplementedError('로그인용 — 탈퇴는 부르지 않는다');

  @override
  Future<String> requestAuthorizationCode() async {
    codeRequests++;
    final current = error;
    if (current != null) {
      throw current;
    }
    return 'apple-one-time-code';
  }
}

UserIdentity _identity(String provider) => UserIdentity(
      id: '$provider-sub',
      userId: 'user-1',
      identityData: {'sub': '$provider-sub'},
      identityId: '$provider-identity',
      provider: provider,
      createdAt: null,
      lastSignInAt: null,
    );

void main() {
  late MockGoTrueClient auth;
  late _FakeAppleClient apple;

  setUp(() {
    auth = MockGoTrueClient();
    apple = _FakeAppleClient();
    // 애플 버튼은 iOS 에서만 있다 — 기본은 iOS 기기에서 탈퇴하는 경우로 둔다(시험 기본값은 android).
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  void signedInWith(List<UserIdentity>? identities) {
    final user = MockUser();
    when(() => user.identities).thenReturn(identities);
    when(() => auth.currentUser).thenReturn(user);
  }

  Future<String?> obtain() => AppleWithdrawalCode(auth, apple).obtain();

  test('애플로 가입한 사람에게는 애플 창을 한 번 띄워 일회용 코드를 받아 온다', () async {
    signedInWith([_identity('apple')]);

    expect(await obtain(), 'apple-one-time-code');
    expect(apple.codeRequests, 1);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    test('iOS 가 아니면(${platform.name}) 애플 사용자여도 애플 창을 띄우지 않는다', () async {
      debugDefaultTargetPlatformOverride = platform;
      signedInWith([_identity('apple')]);

      expect(await obtain(), isNull);
      expect(apple.codeRequests, 0);
    });
  }

  for (final provider in ['kakao', 'google']) {
    test('$provider 사용자에게는 애플 창을 띄우지 않는다', () async {
      signedInWith([_identity(provider)]);

      expect(await obtain(), isNull);
      expect(apple.codeRequests, 0);
    });
  }

  test('연결 정보(identities)가 없거나 세션이 없으면 애플 창을 띄우지 않는다', () async {
    signedInWith(null);
    expect(await obtain(), isNull);

    when(() => auth.currentUser).thenReturn(null);
    expect(await obtain(), isNull);

    expect(apple.codeRequests, 0);
  });

  group('애플 창을 닫거나 실패하면 null — 탈퇴는 막지 않는다', () {
    final errors = <String, Object>{
      '취소(canceled)': const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'hong@privaterelay.appleid.com',
      ),
      '실패(failed)': const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.failed,
        message: 'hong@privaterelay.appleid.com',
      ),
      '지원하지 않는 기기': const SignInWithAppleNotSupportedException(message: 'hong@privaterelay.appleid.com'),
      '플랫폼 오류': PlatformException(code: 'ERROR', message: 'hong@privaterelay.appleid.com'),
    };
    for (final MapEntry(key: name, value: error) in errors.entries) {
      test(name, () async {
        final logs = <String>[];
        final original = debugPrint;
        debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
        addTearDown(() => debugPrint = original);
        signedInWith([_identity('apple')]);
        apple.error = error;

        expect(await obtain(), isNull);
        // 오류 종류 이름만 남긴다 — 문구에 이메일 같은 값이 들어 있을 수 있다.
        expect(logs.join('\n'), isNot(contains('hong@')));
      });
    }
  });
}
