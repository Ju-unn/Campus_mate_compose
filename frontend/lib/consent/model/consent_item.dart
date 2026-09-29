import 'package:campus_mate/consent/model/consent_links.dart';

/// 약관 동의(02-c) 줄. 순서가 화면 순서다.
enum ConsentItem {
  terms('이용약관', wireName: 'terms'),
  privacy('개인정보 수집·이용', wireName: 'privacy'),
  sensitiveReligion('민감정보(종교) 처리', wireName: 'sensitive_religion'),
  overseasTransfer('개인정보 국외 이전\n(OpenAI 등)', wireName: 'overseas_transfer'),
  // 선택 항목은 서버 user_consents 가 아니라 notification_settings.marketing 이 맡는다(계획서 Q4).
  marketing('마케팅 알림 받기');

  const ConsentItem(this.label, {this.wireName});

  /// pen 02-c 줄 글. 국외 이전은 pen 처럼 줄을 직접 바꾼다.
  final String label;

  /// 서버 app/consents/policy.py REQUIRED_KINDS 와 같은 글자. 선택 항목은 null.
  final String? wireName;

  bool get isRequired => wireName != null;

  /// "보기"로 여는 노션 항. 마케팅은 보기가 없다.
  Uri? get link => switch (this) {
        ConsentItem.terms => termsLink,
        ConsentItem.privacy || ConsentItem.sensitiveReligion => privacyItemsLink,
        ConsentItem.overseasTransfer => overseasTransferLink,
        ConsentItem.marketing => null,
      };
}
