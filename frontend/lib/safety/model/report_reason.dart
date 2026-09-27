/// 신고 사유 다섯 개(결정 1 — 한 벌 고정). 서버 `reasons.py` 와 **값과 순서만** 맞춘다 —
/// 한쪽만 고치면 앱이 보낸 값을 서버가 422 로 막는다. 문구는 맞추지 않는다: 서버 문구는 운영자가 보는 말이고,
/// 앱은 pen `yl8gX` 행 문구를 쓴다.
enum ReportReason {
  abuse('abuse', '욕설·비방·혐오'),
  sexual('sexual', '성적 불쾌감'),
  spam('spam', '광고·스팸'),
  fake('fake', '사칭·허위'),

  /// 이것만 한 줄 메모를 받는다(계획서 A1).
  other('other', '기타');

  const ReportReason(this.wire, this.label);

  /// 서버에 보내는 값. `name` 과 같지만 enum 이름을 바꿔도 서버 계약이 흔들리지 않게 따로 둔다.
  final String wire;

  /// 시트 라디오에 보이는 문구(pen `yl8gX` — xarhn · AMxAh · w8qR7 · BHphm · YhPFL).
  final String label;
}

/// 기타 메모 상한. 코드포인트(runes) 기준으로 자르는 것은 화면 입력기의 몫이다.
const int reportNoteMaxLength = 200;
