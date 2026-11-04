import 'dart:async';

import 'package:campus_mate/auth/social/model/data/social_provider.dart';
import 'package:campus_mate/auth/social/model/repository/social_login_repository.dart';
import 'package:campus_mate/common/result.dart';

/// 테스트 전용 [SocialLoginRepository]. 기본은 [completer] 를 끝낼 때까지 기다린다 —
/// 진행 중(스피너 · 다른 버튼 비활성)을 관찰하려고. [nextResult] 를 주면 바로 그 결과를 돌려준다.
class FakeSocialLoginRepository implements SocialLoginRepository {
  FakeSocialLoginRepository({this.nextResult});

  Result<void>? nextResult;
  Completer<Result<void>> completer = Completer<Result<void>>();
  final List<SocialProvider> requested = [];
  int signOutProvidersCalls = 0;

  /// 심사원 로그인: [signInWithPassword] 가 받은 (이메일, 비밀번호). 시험 값은 모두 가짜다.
  final List<(String, String)> passwordRequests = [];

  /// 심사원 로그인에서 돌려줄 결과. null 이면 [passwordCompleter] 를 끝낼 때까지 기다린다.
  Result<void>? nextPasswordResult;
  Completer<Result<void>> passwordCompleter = Completer<Result<void>>();

  @override
  Future<void> signOutProviders() async {
    signOutProvidersCalls++;
  }

  @override
  Future<Result<void>> signInWithPassword(String email, String password) {
    passwordRequests.add((email, password));
    final result = nextPasswordResult;
    if (result != null) {
      return Future.delayed(Duration.zero, () => result);
    }
    return passwordCompleter.future;
  }

  @override
  Future<Result<void>> signIn(SocialProvider provider) {
    requested.add(provider);
    final result = nextResult;
    if (result != null) {
      return Future.delayed(Duration.zero, () => result);
    }
    return completer.future;
  }
}
