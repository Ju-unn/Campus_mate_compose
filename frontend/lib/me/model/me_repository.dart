import 'package:campus_mate/common/result.dart';
import 'package:campus_mate/matching/model/card_detail.dart';
import 'package:campus_mate/me/model/my_profile.dart';
import 'package:campus_mate/me/model/photo_slot.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

/// 화면 15 와 편집 화면이 쓰는 서버 호출. 화면은 이 인터페이스만 보고 구현을 모른다.
abstract interface class MeRepository {
  Future<Result<MyProfile>> fetchProfile();

  /// 15-4 남이 보는 내 프로필 — 상대가 10b · 14c 에서 보는 것과 같은 카드 몸통. 실사진 · 카카오톡 아이디는 없다.
  Future<Result<CardDetail>> fetchCardPreview();

  /// 보낸 칸만 고친다 — null 인 칸은 본문에서 뺀다(서버 `PATCH /me/profile` 은 받은 칸만 쓴다).
  /// 15c 는 [bio], 15-6 은 [nickname] · [heightCm] · [mbti] · [religion] · [isSmoker] · [appearance] 를 보낸다.
  ///
  /// MBTI 만 "선택 안 함" 이 있다 — 안 건드리면 둘 다 비우고, 글자로 바꾸면 [mbti], 비우려면 [clearMbti] 를 켠다
  /// (본문 `"mbti": null`). 얼굴상과 인상은 한 쌍이라 [appearance] 레코드로만 받는다(서버는 한쪽만 오면 422).
  Future<Result<void>> updateProfile({
    String? bio,
    String? nickname,
    int? heightCm,
    String? mbti,
    bool clearMbti = false,
    Religion? religion,
    bool? isSmoker,
    ({AnimalType animalType, ImpressionType impressionType})? appearance,
  });

  /// 15-7 사진 수정 — 칸 [slots] 순서 그대로 한 번에 저장한다(U2). [avatarSource] 는 아바타 원본이 될 칸 번호(0부터).
  Future<Result<void>> savePhotos(List<PhotoSlot> slots, int avatarSource);
}
