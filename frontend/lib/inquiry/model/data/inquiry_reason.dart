/// 문의 사유 여섯 개(pen 21b 순서). 서버 `backend/app/inquiries/reasons.py` 의 `Reason` 과 **값과 순서만** 맞춘다 —
/// 한쪽만 고치면 앱이 보낸 값을 서버가 422 로 막는다. 문구는 맞추지 않는다: 서버 문구는 운영자가 보는 말이고
/// 앱은 pen 사유 시트 행 문구를 쓴다(글자는 view 의 `inquiry_reason_text.dart`).
enum InquiryReason {
  account('account'),
  payment('payment'),
  matching('matching'),
  safety('safety'),
  bug('bug'),
  other('other');

  const InquiryReason(this.wire);

  /// 서버에 보내는 값. `name` 과 같지만 enum 이름을 바꿔도 서버 계약이 흔들리지 않게 따로 둔다.
  final String wire;
}

/// 내용 상한(서버 `BODY_MAX`, DB check 와 같다). 코드포인트(runes) 기준으로 자르는 것은 화면 입력기의 몫이다.
const int inquiryBodyMaxLength = 1000;
