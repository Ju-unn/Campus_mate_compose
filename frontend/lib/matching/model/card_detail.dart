import 'package:campus_mate/matching/model/card_profile.dart';
import 'package:campus_mate/profile/model/profile_enums.dart';

/// 10b 상대 프로필 상세(`TORAs`). 카드 앞면보다 많은 것을 보여주지만
/// 실사진·카카오톡 아이디는 여전히 없다 — 그건 신뢰 확인(조각 5) 뒤다.
class CardDetail {
  const CardDetail({
    required this.cardId,
    required this.profile,
    required this.survey,
    required this.animalType,
    required this.impressionType,
    required this.religion,
    required this.isSmoker,
    required this.interests,
    required this.myTraits,
    required this.idealTraits,
    this.heightCm,
    this.mbti,
    this.studentNumber,
    this.bio,
    this.idealNote,
  });

  final String cardId;
  final CardProfile profile;

  /// 9축 성향 값(-1.0 ~ 1.0). 축 순서는 05-01 활동성 … 05-09 새로움이다.
  final List<double> survey;
  final AnimalType animalType;
  final ImpressionType impressionType;
  final Religion religion;
  final bool isSmoker;
  final List<String> interests;
  final List<String> myTraits;
  final List<String> idealTraits;
  final int? heightCm;
  final String? mbti;
  final String? studentNumber;
  final String? bio;
  final String? idealNote;

  factory CardDetail.fromJson(Map<String, dynamic> json) {
    return CardDetail(
      cardId: json['card_id'] as String,
      profile: CardProfile.fromJson(json['profile'] as Map<String, dynamic>),
      survey: (json['survey'] as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
      animalType: AnimalType.values.byName(json['animal_type'] as String),
      impressionType: ImpressionType.values.byName(json['impression_type'] as String),
      religion: Religion.values.byName(json['religion'] as String),
      isSmoker: json['is_smoker'] as bool,
      interests: _strings(json['interests']),
      myTraits: _strings(json['my_traits']),
      idealTraits: _strings(json['ideal_traits']),
      heightCm: json['height_cm'] as int?,
      mbti: json['mbti'] as String?,
      studentNumber: json['student_number'] as String?,
      bio: json['bio'] as String?,
      idealNote: json['ideal_note'] as String?,
    );
  }
}

List<String> _strings(Object? value) =>
    (value as List<dynamic>? ?? const []).map((v) => v as String).toList();
