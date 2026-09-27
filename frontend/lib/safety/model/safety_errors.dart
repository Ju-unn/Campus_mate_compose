import 'package:campus_mate/common/failure.dart';

/// 서버가 신고에 돌려주는 거절 문구(backend `app/safety/`). 앱은 상태코드를 못 보고 문구만 받으므로,
/// **시트를 닫을지가 달라지는 것들만** 여기서 알아본다.
const String _alreadyReported = '이미 신고한 사용자예요'; // 409
const String _profileGone = '프로필을 찾을 수 없어요'; // 404
const String _messageGone = '메시지를 찾을 수 없어요'; // 404

/// 429 는 문구 없이 [RateLimitedFailure] 로 온다. 공용 문구("잠시 후 다시 시도")는 하루 상한과 맞지 않다 —
/// 기다려도 오늘은 안 된다.
const String reportLimitedMessage = '오늘은 더 신고할 수 없어요';

/// 같은 사람을 두 번 신고했다. 첫 요청이 사실은 성공하고 응답만 잃었을 수도 있어 **끝난 것으로 친다**.
bool isAlreadyReported(Failure failure) => failure.toDisplayMessage() == _alreadyReported;

/// 신고하려던 프로필 · 메시지가 서버에 없다. 다시 보내도 같은 답이라 시트를 닫는다.
bool isReportTargetGone(Failure failure) =>
    isProfileGone(failure) || failure.toDisplayMessage() == _messageGone;

/// 14c 가 보여 줄 상대가 없다(`GET /profiles/{id}` 404). 서버가 차단 · 나감 · 탈퇴를 일부러 한 문구로 묶는다.
bool isProfileGone(Failure failure) => failure.toDisplayMessage() == _profileGone;

/// 신고 시트에 띄울 문구. 하루 상한만 바꿔 치고 나머지는 서버 문구를 그대로 쓴다.
String reportFailureMessage(Failure failure) =>
    failure is RateLimitedFailure ? reportLimitedMessage : failure.toDisplayMessage();
