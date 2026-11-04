/// 기기 연락처 한 사람. 번호는 기기에 적힌 원문 그대로다 — 정규화는 서버 한 곳에서만 한다(Ruling 32).
class DeviceContact {
  const DeviceContact({required this.id, required this.name, required this.numbers});

  final String id;
  final String name;
  final List<String> numbers;
}
