import 'package:campus_mate/common/failure.dart';

/// 서버가 지인 리뷰에 돌려주는 거절 문구(backend `app/core/errors.py`
/// `FRIEND_REVIEW_ALREADY_WRITTEN`). 앱은 상태코드를 못 보고 문구만 받으므로,
/// 화면 흐름이 달라지는 것만 여기서 알아본다(safety_errors.dart · chat_errors.dart 와 같은 자리).
// l10n-ignore-start(server-text): 서버 errors.py 문구와 글자까지 같아야 하는 비교 상수 — ARB 로 옮기면 분기가 조용히 죽는다
const String _alreadyWritten = '이미 리뷰를 남겼어요'; // 409
const String _reviewGone = '리뷰를 찾을 수 없어요'; // 404 — 20e 지우기

const String _codeNotFound = '코드를 찾을 수 없어요'; // 404 — 20f 확인 · 코드로 쓰기(backend friend_reviews/router.py FRIEND_CODE_NOT_FOUND)
// l10n-ignore-end

bool _isServerText(Failure failure, String text) => failure is ServerRejectedFailure && failure.serverMessage == text;

/// 20b 를 열기 전(`fetchTarget`)이 409 — 계획서 P3, 시트 대신 토스트로 안내한다.
bool isAlreadyWritten(Failure failure) => _isServerText(failure, _alreadyWritten);

/// 20f 확인이 404 — 없는 코드 · 막힌 사람 · 본인 모두 이 하나다(서버가 이유를 가르지 않는다).
bool isFriendCodeNotFound(Failure failure) => _isServerText(failure, _codeNotFound);

/// 20f 확인 · 코드로 쓰기가 429(실패가 잦거나 하루 상한). `http_send` 가 429 를 [RateLimitedFailure] 로 바꾼다.
bool isFriendCodeTryLater(Failure failure) => failure is RateLimitedFailure;

/// 화면에 띄울 실패. 429 만 이 앱 문구("잠시 후 다시 시도해 주세요.", pen Mi3ux/XATaU)의 종류로 고정하고 나머지(404 · 409 등)는 그대로다.
Failure friendReviewFailure(Failure failure) =>
    isFriendCodeTryLater(failure) ? const AppErrorFailure(AppError.friendCodeTryLater) : failure;

/// 20e 에서 지우려던 리뷰가 서버에 이미 없다 — 목록에서도 뺀다(남겨 두면 다시 눌러도 404 뿐이다).
bool isReviewGone(Failure failure) => _isServerText(failure, _reviewGone);
