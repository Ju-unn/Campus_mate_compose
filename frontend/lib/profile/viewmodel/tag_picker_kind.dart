// enum 멤버 이름(myTraits·idealTraits)이 tags.dart 의 같은 이름 상수와 겹쳐 별칭을 준다
// (겹치면 enum 본문 안에서 자기 자신을 가리켜 순환 참조 컴파일 에러가 난다).
import 'package:campus_mate/profile/model/tags.dart' as tag_pool;

/// 관심사(04-5)·나의 특징(04-6)·이상형 특징(06-2) 세 화면은 헤드라인·풀·저장 API 만 다르고
/// 위젯 구조가 같아 한 화면 + 이 enum 으로 합친다(백엔드 tags.py 세 상수, B9 세 엔드포인트와 1:1 대응).
enum TagPickerKind {
  interests(pool: tag_pool.interestTags, endpoint: 'interests', headline: '관심사를 골라주세요'),
  myTraits(pool: tag_pool.myTraits, endpoint: 'my-traits', headline: '나를 표현하는 특징을 골라주세요'),
  idealTraits(pool: tag_pool.idealTraits, endpoint: 'ideal-traits', headline: '어떤 분을 만나고 싶나요?');

  const TagPickerKind({required this.pool, required this.endpoint, required this.headline});

  final List<String> pool;
  final String endpoint;
  final String headline;
}
