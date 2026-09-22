import 'package:campus_mate/common/failure.dart';

/// 서버가 409 로 돌려주는 채팅 쪽 문구(backend `app/core/errors.py`).
/// 앱은 상태코드를 못 보고 문구만 받으므로, **동작이 달라져야 하는 것들만** 여기서 알아본다.
const String _chatClosed = '종료된 대화예요';
const String _chatLeft = '이미 나간 대화예요';
const String _trustDeadlinePassed = '응답 기한이 지났어요';

/// 기한이 지난 것과 이미 닫힌 것은 **사용자에게 같은 상황**이다 — 문장을 하나로 묶는다.
const String gateOverMessage = '응답 기한이 지나 이 대화는 종료됐어요';

/// 화면에 띄울 문구. 위 두 가지만 바꿔 치고 나머지는 서버 문구를 그대로 쓴다.
String chatFailureMessage(Failure failure) {
  final message = failure.toDisplayMessage();
  return message == _chatClosed || message == _trustDeadlinePassed ? gateOverMessage : message;
}

/// 나가기를 두 번 눌렀거나 재시도한 경우. **이미 나갔다면 원하던 결과가 이미 났다** —
/// 실패로 다루면 목록으로 못 돌아가고 방에 갇힌다.
bool isAlreadyLeft(Failure failure) => failure.toDisplayMessage() == _chatLeft;
