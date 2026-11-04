/// 19 코호트 대기(pen `tUaGw`) — 우리 학교가 아직 첫 카드를 안 열었을 때 메인 대신 그리는 값.
class CohortWait {
  const CohortWait({required this.firstCardAt, required this.recruitCount});

  /// 첫 카드 시각. 기기 시간대로 바꿔 둔다 — D-숫자를 기기 달력 날짜로 센다.
  final DateTime firstCardAt;

  /// 우리 학교에서 가입을 끝낸 사람 수
  final int recruitCount;
}
