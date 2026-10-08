import 'package:campus_mate/auth/model/social_login_repository.dart';
import 'package:campus_mate/common/result.dart';

/// 테스트 전용 [IdTokenGateway]. 정해 둔 결과를 돌려주고 불린 횟수를 센다.
class FakeIdTokenGateway implements IdTokenGateway {
  FakeIdTokenGateway(this.result);

  Result<SocialCredential> result;
  int calls = 0;
  int signOutCalls = 0;

  /// 앱 로그아웃 때 불린다. 실제 게이트웨이처럼 실패를 삼키는지는 각 게이트웨이 시험이 본다.
  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Future<Result<SocialCredential>> obtainCredential() async {
    calls++;
    return result;
  }
}
