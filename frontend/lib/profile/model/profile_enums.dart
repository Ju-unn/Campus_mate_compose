/// 동물상 8종 확정(DESIGN.md §5.4, 백엔드 public.animal_type 과 값이 같다).
enum AnimalType { dog, cat, fox, bear, rabbit, deer, wolf, hamster }

/// 인상 5종(백엔드 public.impression_type 과 값이 같다).
enum ImpressionType { arab, tofu, kind, chic, innocent }

/// 종교 4종(백엔드 public.religion 과 값이 같다).
enum Religion { none, protestant, catholic, buddhist }

/// 화면에 쓰는 한글 라벨. 04-4(본인)와 06-1(선호)이 같은 문구를 쓴다(DESIGN.md §8.5).
extension AnimalTypeLabel on AnimalType {
  String get label => switch (this) {
        AnimalType.dog => '강아지상',
        AnimalType.cat => '고양이상',
        AnimalType.fox => '여우상',
        AnimalType.bear => '곰상',
        AnimalType.rabbit => '토끼상',
        AnimalType.deer => '사슴상',
        AnimalType.wolf => '늑대상',
        AnimalType.hamster => '햄스터상',
      };

  /// `animal-face-*-2d-v1.png` 일러스트 아이콘 경로(DESIGN.md §5.4).
  String get iconAsset => 'assets/images/animal-face-$name-2d-v1.png';
}

extension ImpressionTypeLabel on ImpressionType {
  String get label => switch (this) {
        ImpressionType.arab => '아랍상',
        ImpressionType.tofu => '두부상',
        ImpressionType.kind => '선한상',
        ImpressionType.chic => '시크상',
        ImpressionType.innocent => '청순상',
      };
}

extension ReligionLabel on Religion {
  String get label => switch (this) {
        Religion.none => '무교',
        Religion.protestant => '기독교',
        Religion.catholic => '천주교',
        Religion.buddhist => '불교',
      };
}
