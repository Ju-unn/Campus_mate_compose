import 'package:campus_mate/common/failure.dart';

/// 서버가 지인 리뷰에 돌려주는 거절 문구(backend `app/core/errors.py`
/// `FRIEND_REVIEW_ALREADY_WRITTEN`). 앱은 상태코드를 못 보고 문구만 받으므로,
/// 화면 흐름이 달라지는 것만 여기서 알아본다(safety_errors.dart · chat_errors.dart 와 같은 자리).
const String _alreadyWritten = '이미 리뷰를 남겼어요'; // 409
const String _reviewGone = '리뷰를 찾을 수 없어요'; // 404 — 20e 지우기

/// 20b 를 열기 전(`fetchTarget`)이 409 — 계획서 P3, 시트 대신 토스트로 안내한다.
bool isAlreadyWritten(Failure failure) => failure.toDisplayMessage() == _alreadyWritten;

/// 20e 에서 지우려던 리뷰가 서버에 이미 없다 — 목록에서도 뺀다(남겨 두면 다시 눌러도 404 뿐이다).
bool isReviewGone(Failure failure) => failure.toDisplayMessage() == _reviewGone;
