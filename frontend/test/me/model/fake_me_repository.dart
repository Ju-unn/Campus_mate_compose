import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/me_repository.dart';
import 'package:campus_mate/me/model/my_profile.dart';

/// 테스트가 돌려줄 값을 직접 정하는 가짜 저장소. 몇 번 불렸는지도 센다("다시 시도" 확인용).
class FakeMeRepository implements MeRepository {
  FakeMeRepository(this.profile);

  Result<MyProfile> profile;
  int calls = 0;

  @override
  Future<Result<MyProfile>> fetchProfile() async {
    calls++;
    return profile;
  }
}
