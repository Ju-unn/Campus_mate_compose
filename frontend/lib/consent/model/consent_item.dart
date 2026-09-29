import 'package:campus_mate/consent/model/consent_links.dart';

/// 약관 동의(02-c) 줄. 순서가 화면 순서다.
/// 09-29 최종 4칸(전체 동의 + 아래 셋) — 종교는 개인정보 수집·이용 안에 넣고, OpenAI 국외 이전은
/// 처리방침 공개로 대신해 줄이 없다(사용자 결정). 서버 enum 의 두 값은 남아 있지만 보내지 않는다.
enum ConsentItem {
  terms('이용약관', wireName: 'terms'),
  privacy('개인정보 수집·이용', wireName: 'privacy'),
  // 선택 항목은 서버 user_consents 가 아니라 notification_settings.marketing 이 맡는다(계획서 Q4).
  marketing('마케팅 알림 받기');

  const ConsentItem(this.label, {this.wireName});

  /// pen 02-c 줄 글.
  final String label;

  /// 서버 app/consents/policy.py REQUIRED_KINDS 와 같은 글자. 선택 항목은 null.
  final String? wireName;

  bool get isRequired => wireName != null;

  /// "보기"로 여는 노션 항. 마케팅은 보기가 없다.
  Uri? get link => switch (this) {
        ConsentItem.terms => termsLink,
        ConsentItem.privacy => privacyItemsLink,
        ConsentItem.marketing => null,
      };
}
