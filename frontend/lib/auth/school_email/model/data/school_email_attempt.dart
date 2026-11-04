import 'package:campus_mate/common/failure.dart';

/// 이 메일로는 다시 해도 같은 답인 실패(409 다른 계정 · 422 거절). 임시 연결과 저장한 임시 토큰을 버린다.
/// 성공도 시도를 끝내지만 실패가 아니라 여기 없다. 저장소와 03 VM 이 같은 규칙을 쓰도록 한곳에 둔다.
bool endsSchoolEmailAttempt(Failure failure) =>
    failure is SchoolEmailTakenFailure || failure is SchoolEmailRejectedFailure;
