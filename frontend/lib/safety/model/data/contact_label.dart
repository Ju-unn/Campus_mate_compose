/// 16b 한 줄에 보일 이름과 가린 번호(pen `GC2LV` — 이름 · 번호 두 줄).
class ContactLabel {
  const ContactLabel({required this.name, required this.maskedNumber});

  final String name;
  final String maskedNumber;
}

/// 한국 국가번호. 연락처 앱은 `+82 10-…` 로도 적는다.
const String _koreaCountryCode = '82';

/// 가린 번호로 보이는 최소 자릿수 — 휴대전화(10~11자리). 이보다 짧은 번호(대표번호 등)는 원문 그대로 둔다.
const int _maskableMinDigits = 10;

/// pen 8d · 16b 처럼 `010-****-2841` 로 가린다. 숫자만 남기고, 앞 `82` 는 떼고 그 뒤 앞자리 0 을 지운 뒤
/// `0` 하나를 붙인다 — 서버 `to_e164` 와 같은 규칙이라 `+82 010-…` 도 `010-…` 이 된다.
String maskPhoneNumber(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  final local = digits.startsWith(_koreaCountryCode)
      ? '0${digits.substring(_koreaCountryCode.length).replaceFirst(RegExp('^0+'), '')}'
      : digits;
  if (local.length < _maskableMinDigits) return raw;
  return '${local.substring(0, 3)}-****-${local.substring(local.length - 4)}';
}
