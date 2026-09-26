import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/my_profile.dart';

/// 화면 15 가 쓰는 서버 호출. 화면은 이 인터페이스만 보고 구현을 모른다.
abstract interface class MeRepository {
  Future<Result<MyProfile>> fetchProfile();
}
