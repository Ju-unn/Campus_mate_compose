import 'package:campus_mate/profile/model/tags.dart' as tag_pool;

/// 관심사(04-5)·나의 특징(04-6)·이상형 특징(06-2) 화면이 서로 다른 점만 모아 둔다.
/// 태그 목록은 서버 tags.py 와 1:1 이다.
enum TagPickerKind {
  interests(
    pool: tag_pool.interestTags,
    endpoint: 'interests',
    headline: '주로 관심 있는 게 뭐예요?',
    subtext: '비슷한 취향을 가진 사람을 먼저 보여드려요.',
    tagName: '관심사 태그',
    dotIndex: 4,
    dotTotal: 6,
  ),
  myTraits(
    pool: tag_pool.myTraits,
    endpoint: 'my-traits',
    headline: '어떤 특징을 가지고 계신가요?',
    subtext: '나를 가장 잘 나타내는 모습을 골라주세요.',
    tagName: '나의 특징',
    dotIndex: 5,
    dotTotal: 6,
  ),
  idealTraits(
    pool: tag_pool.idealTraits,
    endpoint: 'ideal-traits',
    headline: '어떤 분을 만나고 싶나요?',
    subtext: '이런 분이면 좋겠다 싶은 모습을 골라주세요.',
    tagName: '이상형 특징',
    dotIndex: 1,
    dotTotal: 3,
  );

  const TagPickerKind({
    required this.pool,
    required this.endpoint,
    required this.headline,
    required this.subtext,
    required this.tagName,
    required this.dotIndex,
    required this.dotTotal,
  });

  final List<String> pool;
  final String endpoint;
  final String headline;
  final String subtext;
  final String tagName;

  /// 세 화면 모두 최소 3개·최대 5개(백엔드 validate_tag_selection 과 같은 규칙, 설계 §6.1·§6.6b).
  static const int minCount = 3;
  static const int maxCount = 5;

  String get tagLabel => '$tagName (최소 $minCount개 · 최대 $maxCount개)';

  /// 진행 점(0부터 센 현재 칸 / 전체 칸).
  final int dotIndex;
  final int dotTotal;
}
