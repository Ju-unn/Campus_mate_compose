import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/me/model/my_profile.dart';

/// 화면 15 와 편집 화면이 쓰는 서버 호출. 화면은 이 인터페이스만 보고 구현을 모른다.
abstract interface class MeRepository {
  Future<Result<MyProfile>> fetchProfile();

  /// 보낸 칸만 고친다 — null 인 칸은 본문에서 뺀다(서버 `PATCH /me/profile` 은 받은 칸만 쓴다).
  /// 15c 는 [bio], 15d 는 [nickname] · [heightCm] 을 보낸다.
  Future<Result<void>> updateProfile({String? bio, String? nickname, int? heightCm});
}
