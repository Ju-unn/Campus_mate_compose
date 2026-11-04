import 'package:campus_mate/common/result.dart';

abstract interface class ReferralRepository {
  /// 화면 20 코드 입력. 성공 값은 추천인 id 다(20b 지인 리뷰가 이 id 로 상대를 불러온다).
  /// 자르기 · 대문자는 서버 DB 함수도 하지만 앱은 입력 포매터로 이미 맞춰서 보낸다.
  Future<Result<String>> redeem(String code);

  /// 내 추천 코드. 홈탭 19 코호트 대기 "친구 초대"가 쓴다. 계정당 하나이고 바뀌지 않는다.
  Future<Result<String>> myCode();
}
