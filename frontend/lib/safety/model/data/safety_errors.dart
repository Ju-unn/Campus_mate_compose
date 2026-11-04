import 'package:campus_mate/common/failure.dart';

/// 서버가 신고에 돌려주는 거절 문구(backend `app/safety/`). 앱은 상태코드를 못 보고 문구만 받으므로,
/// **시트를 닫을지가 달라지는 것들만** 여기서 알아본다.
// l10n-ignore-start(server-text): 서버 errors.py 문구와 글자까지 같아야 하는 비교 상수 — ARB 로 옮기면 분기가 조용히 죽는다
const String _alreadyReported = '이미 신고를 완료했어요'; // 409 — 서버 errors.py ALREADY_REPORTED 와 글자까지 같아야 한다
const String _profileGone = '프로필을 찾을 수 없어요'; // 404
const String _messageGone = '메시지를 찾을 수 없어요'; // 404
const String _friendReviewGone = '리뷰를 찾을 수 없어요'; // 404 — 받은 리뷰가 아니거나 그새 가려졌다
const String _pollGone = '질문을 찾을 수 없어요'; // 404 — 그새 지워졌거나 가려진 투표 글
// l10n-ignore-end

bool _isServerText(Failure failure, bool Function(String text) matches) =>
    failure is ServerRejectedFailure && matches(failure.serverMessage);

/// 같은 대상(프로필 · 메시지 · 리뷰 · 투표 글)을 두 번 신고했다. 첫 요청이 사실은 성공하고 응답만 잃었을 수도 있어
/// **끝난 것으로 친다**.
bool isAlreadyReported(Failure failure) => _isServerText(failure, (text) => text == _alreadyReported);

/// 신고하려던 프로필 · 메시지 · 리뷰 · 투표 글이 서버에 없다. 다시 보내도 같은 답이라 시트를 닫는다.
bool isReportTargetGone(Failure failure) =>
    isProfileGone(failure) ||
    _isServerText(failure, const {_messageGone, _friendReviewGone, _pollGone}.contains);

/// 14c 가 보여 줄 상대가 없다(`GET /profiles/{id}` 404). 서버가 차단 · 나감 · 탈퇴를 일부러 한 문구로 묶는다.
bool isProfileGone(Failure failure) => _isServerText(failure, (text) => text == _profileGone);

/// 신고 시트에 띄울 실패. 429 는 [RateLimitedFailure] 로 오는데 이 앱 문구(`AppError.reportLimited`)의 종류로 바꿔 낀다 —
/// 공용 문구("잠시 후 다시 시도")는 하루 상한과 맞지 않다(기다려도 오늘은 안 된다). 나머지는 그 실패 그대로다.
Failure reportFailure(Failure failure) =>
    failure is RateLimitedFailure ? const AppErrorFailure(AppError.reportLimited) : failure;
