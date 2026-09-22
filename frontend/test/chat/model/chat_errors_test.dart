import 'package:campus_mate/chat/model/chat_errors.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기한이 지난 것과 이미 닫힌 것은 같은 안내로 묶는다', () {
    // 사용자에게는 같은 상황이다 — 서버가 왜 두 코드로 나누는지는 화면이 알 바 아니다.
    expect(chatFailureMessage(const ServerRejectedFailure('응답 기한이 지났어요')), gateOverMessage);
    expect(chatFailureMessage(const ServerRejectedFailure('종료된 대화예요')), gateOverMessage);
  });

  test('그 밖의 문구는 서버가 준 대로 보여준다', () {
    expect(
      chatFailureMessage(const ServerRejectedFailure('상대가 대화를 나갔어요')),
      '상대가 대화를 나갔어요',
    );
    expect(chatFailureMessage(const NetworkFailure()), '네트워크 연결을 확인해 주세요');
  });

  test('이미 나간 대화는 나가기 재시도의 성공으로 친다', () {
    expect(isAlreadyLeft(const ServerRejectedFailure('이미 나간 대화예요')), isTrue);
    expect(isAlreadyLeft(const ServerRejectedFailure('종료된 대화예요')), isFalse);
  });
}
