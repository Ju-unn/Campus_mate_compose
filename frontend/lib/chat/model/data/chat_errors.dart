import 'package:campus_mate/common/failure.dart';

/// 서버가 409 로 돌려주는 채팅 쪽 문구(backend `app/core/errors.py` CHAT_CLOSED · CHAT_LEFT · TRUST_DEADLINE_PASSED · TRUST_ALREADY_ANSWERED).
/// 앱은 상태코드를 못 보고 문구만 받으므로, **동작이 달라져야 하는 것들만** 여기서 알아본다.
// l10n-ignore-start(server-text): 서버 errors.py 문구와 글자까지 같아야 하는 비교 상수 — ARB 로 옮기면 분기가 조용히 죽는다
const String _chatClosed = '종료된 대화예요';
const String _chatLeft = '이미 나간 대화예요';
const String _trustDeadlinePassed = '응답 기한이 지났어요';
const String _trustAlreadyAnswered = '이미 수락했어요';
// l10n-ignore-end

bool _isServerText(Failure failure, String text) => failure is ServerRejectedFailure && failure.serverMessage == text;

/// 화면에 띄울 실패. 기한이 지난 것과 이미 닫힌 것은 **사용자에게 같은 상황**이라 앱이 정한 하나의 종류
/// ([AppError.chatGateOver])로 묶고, 나머지는 그대로 돌려준다(서버 문구는 서버가 준 대로 보인다).
Failure chatFailure(Failure failure) => _isServerText(failure, _chatClosed) || _isServerText(failure, _trustDeadlinePassed)
    ? const AppErrorFailure(AppError.chatGateOver)
    : failure;

/// 나가기를 두 번 눌렀거나 재시도한 경우. **이미 나갔다면 원하던 결과가 이미 났다** —
/// 실패로 다루면 목록으로 못 돌아가고 방에 갇힌다.
bool isAlreadyLeft(Failure failure) => _isServerText(failure, _chatLeft);

/// 수락을 두 번 보냈다. **이미 수락돼 있으면 원하던 결과가 이미 났다** —
/// 오류로 띄우면 수락해 놓고 실패한 것처럼 보인다.
bool isTrustAlreadyAnswered(Failure failure) => _isServerText(failure, _trustAlreadyAnswered);
