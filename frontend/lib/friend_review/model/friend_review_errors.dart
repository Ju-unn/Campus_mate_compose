import 'package:campus_mate/common/failure.dart';

/// 서버가 지인 리뷰에 돌려주는 거절 문구(backend `app/core/errors.py`
/// `FRIEND_REVIEW_ALREADY_WRITTEN`). 앱은 상태코드를 못 보고 문구만 받으므로,
/// 화면 흐름이 달라지는 것만 여기서 알아본다(safety_errors.dart · chat_errors.dart 와 같은 자리).
const String _alreadyWritten = '이미 리뷰를 남겼어요'; // 409
const String _reviewGone = '리뷰를 찾을 수 없어요'; // 404 — 20e 지우기

const String _codeNotFound = '코드를 찾을 수 없어요'; // 404 — 20f 확인 · 코드로 쓰기(backend friend_reviews/router.py FRIEND_CODE_NOT_FOUND)

/// 20f 확인 · 코드로 쓰기의 429(backend FRIEND_CODE_TRY_LATER 와 같은 글자). `http_send` 가 429 를
/// [RateLimitedFailure] 로 바꾸며 서버 문구를 버려 여기서 되살린다 — pen Mi3ux/XATaU 문구와 같다.
const String friendCodeTryLaterMessage = '잠시 후 다시 시도해 주세요.';

/// 20b 를 열기 전(`fetchTarget`)이 409 — 계획서 P3, 시트 대신 토스트로 안내한다.
bool isAlreadyWritten(Failure failure) => failure.toDisplayMessage() == _alreadyWritten;

/// 20f 확인이 404 — 없는 코드 · 막힌 사람 · 본인 모두 이 하나다(서버가 이유를 가르지 않는다).
bool isFriendCodeNotFound(Failure failure) => failure.toDisplayMessage() == _codeNotFound;

/// 20f 확인 · 코드로 쓰기가 429(실패가 잦거나 하루 상한).
bool isFriendCodeTryLater(Failure failure) => failure is RateLimitedFailure;

/// 화면에 띄울 문구. 429 만 서버 문구로 돌려놓고 나머지(404 · 409 등)는 서버 문구 그대로다.
String friendReviewFailureMessage(Failure failure) =>
    isFriendCodeTryLater(failure) ? friendCodeTryLaterMessage : failure.toDisplayMessage();

/// 20e 에서 지우려던 리뷰가 서버에 이미 없다 — 목록에서도 뺀다(남겨 두면 다시 눌러도 404 뿐이다).
bool isReviewGone(Failure failure) => failure.toDisplayMessage() == _reviewGone;
