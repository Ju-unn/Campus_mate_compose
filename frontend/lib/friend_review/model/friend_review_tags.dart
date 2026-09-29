/// 20b 가 보여 줄 태그 12종. DESIGN §13-25 순서 그대로 — 서버 `TAGS`(backend
/// `app/friend_reviews/router.py`)와 같은 목록이다. **외모 태그는 없다**(계획서 결정).
const List<String> friendReviewTags = [
  '약속을 잘 지켜요',
  '대화가 편해요',
  '배려가 깊어요',
  '유머 감각이 좋아요',
  '성실해요',
  '솔직해요',
  '이야기를 잘 들어줘요',
  '긍정적이에요',
  '센스 있어요',
  '다정해요',
  '차분해요',
  '리액션이 좋아요',
];

/// 한 리뷰에 고를 수 있는 태그 수(서버와 같음, 0개 · 4개는 422).
const int friendReviewMaxTags = 3;

/// 한마디 최대 글자 수(서버와 같음, 101자는 422).
const int friendReviewCommentMaxLength = 100;
