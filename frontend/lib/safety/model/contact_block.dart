/// 서버 한 번에 받는 번호 수(`backend/app/safety/reasons.py` CONTACT_BLOCK_BATCH_MAX 와 같아야 한다).
/// 넘기면 422 라서 저장소가 나눠 보낸다.
const int contactBlockBatchMax = 200;

/// 서버가 아는 지인 차단 한 건. 이름 · 번호는 없다 — 이름은 기기 파일(`ContactNameStore`)에만 있다.
class ContactBlock {
  const ContactBlock({required this.id, required this.createdAt});

  final String id;
  final DateTime createdAt;
}
