/// 동물상 8종 확정(DESIGN.md §5.4, 백엔드 public.animal_type 과 값이 같다).
enum AnimalType { dog, cat, fox, bear, rabbit, deer, wolf, hamster }

/// 인상 5종(백엔드 public.impression_type 과 값이 같다).
enum ImpressionType { arab, tofu, kind, chic, innocent }

/// 종교 4종(백엔드 public.religion 과 값이 같다).
enum Religion { none, protestant, catholic, buddhist }

/// 20d 유입경로 칩 5개(DESIGN.md §9 화면 20d). `name` 이 곧 서버 값이다(백엔드 public.acquisition_channel).
/// 칩 글자는 view 의 `AcquisitionChannelText.label` 이 정한다(문구 파일 ARB).
enum AcquisitionChannel { everytime, instagram, friend, community, other }

/// 화면 글자(강아지상 · 아랍상 · 무교 …)는 view 의 `profile_enum_text.dart` 가 정한다(문구 파일 ARB).
extension AnimalTypeIcon on AnimalType {
  /// `animal-face-*-2d-v1.png` 일러스트 아이콘 경로(DESIGN.md §5.4).
  String get iconAsset => 'assets/images/animal-face-$name-2d-v1.png';
}
