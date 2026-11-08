import 'package:campus_mate/core/draft/draft_screen.dart';
import 'package:campus_mate/profile/traits/model/data/tags.dart' as tag_pool;

/// 관심사(04-5)·나의 특징(04-6)·이상형 특징(06-2) 화면이 서로 다른 점만 모아 둔다.
/// 태그 목록은 서버 tags.py 와 1:1 이다. 제목 · 부제 · 태그 이름 글자는 view 의 `TagPickerKindText` 가 정한다(문구 파일 ARB).
enum TagPickerKind {
  interests(
    pool: tag_pool.interestTags,
    endpoint: 'interests',
    draftScreen: DraftScreen.interests,
    dotIndex: 4,
    dotTotal: 6,
  ),
  myTraits(
    pool: tag_pool.myTraits,
    endpoint: 'my-traits',
    draftScreen: DraftScreen.myTraits,
    dotIndex: 5,
    dotTotal: 6,
  ),
  idealTraits(
    pool: tag_pool.idealTraits,
    endpoint: 'ideal-traits',
    draftScreen: DraftScreen.idealTraits,
    dotIndex: 1,
    dotTotal: 3,
  );

  const TagPickerKind({
    required this.pool,
    required this.endpoint,
    required this.draftScreen,
    required this.dotIndex,
    required this.dotTotal,
  });

  final List<String> pool;
  final String endpoint;

  /// 온보딩에서 쓰던 선택을 폰에 임시 저장하는 자리. 세 화면이 서로 섞이지 않게 따로 둔다.
  final DraftScreen draftScreen;

  /// 세 화면 모두 최소 3개·최대 5개(백엔드 validate_tag_selection 과 같은 규칙, 설계 §6.1·§6.6b).
  static const int minCount = 3;
  static const int maxCount = 5;

  /// 진행 점(0부터 센 현재 칸 / 전체 칸).
  final int dotIndex;
  final int dotTotal;
}
