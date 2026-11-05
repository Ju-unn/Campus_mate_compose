import 'package:campus_mate/chat/model/data/chat_errors.dart';
import 'package:campus_mate/common/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기한이 지난 것과 이미 닫힌 것은 같은 안내(종류)로 묶는다', () {
    // 사용자에게는 같은 상황이다 — 서버가 왜 두 코드로 나누는지는 화면이 알 바 아니다.
    for (final detail in ['응답 기한이 지났어요', '종료된 대화예요']) {
      expect(
        chatFailure(ServerRejectedFailure(detail)),
        isA<AppErrorFailure>().having((failure) => failure.error, 'error', AppError.chatGateOver),
        reason: detail,
      );
    }
  });

  test('그 밖의 실패는 그대로 돌려준다(서버 문구도 서버가 준 대로)', () {
    const other = ServerRejectedFailure('상대가 대화를 나갔어요');
    const network = NetworkFailure();

    expect(chatFailure(other), same(other));
    expect(chatFailure(network), same(network));
  });

  test('이미 나간 대화는 나가기 재시도의 성공으로 친다', () {
    expect(isAlreadyLeft(const ServerRejectedFailure('이미 나간 대화예요')), isTrue);
    expect(isAlreadyLeft(const ServerRejectedFailure('종료된 대화예요')), isFalse);
    expect(isAlreadyLeft(const NetworkFailure()), isFalse);
  });

  test('이미 수락한 409 는 수락 재시도의 성공으로 친다', () {
    expect(isTrustAlreadyAnswered(const ServerRejectedFailure('이미 수락했어요')), isTrue);
    expect(isTrustAlreadyAnswered(const ServerRejectedFailure('응답 기한이 지났어요')), isFalse);
    expect(isTrustAlreadyAnswered(const UnknownFailure()), isFalse);
  });
}
