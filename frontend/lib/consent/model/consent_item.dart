import 'package:campus_mate/consent/model/consent_links.dart';

/// 설명 줄 안에서 굵게(700) 보이는 말 — 민감정보라 같은 줄 안에서 눈에 띄게 한다.
const consentDetailEmphasis = '종교(민감정보)';

/// 약관 동의(02-c) 줄. 순서가 화면 순서다.
/// 09-29 최종 4칸(전체 동의 + 아래 셋) — 종교는 개인정보 수집·이용 안에 넣고, OpenAI 국외 이전은
/// 처리방침 공개로 대신해 줄이 없다(사용자 결정). 서버 enum 의 두 값은 남아 있지만 보내지 않는다.
/// 10-15 안 B: 줄 글은 그대로 두고, 개인정보 줄 아래에 무엇을 · 왜 · 얼마나 받는지 늘 보이는 설명을 단다.
enum ConsentItem {
  terms('이용약관', wireName: 'terms'),
  privacy('개인정보 수집·이용', wireName: 'privacy', details: [
    '수집: 프로필·사진·$consentDetailEmphasis 등',
    '이용: 매칭, AI 아바타(사진 1장을 미국 OpenAI로 전송, 학습 미사용)',
    '보관: 탈퇴 후 30일 · 동의하지 않으면 가입할 수 없어요',
  ]),
  // 선택 항목은 서버 user_consents 가 아니라 notification_settings.marketing 이 맡는다(계획서 Q4).
  marketing('마케팅 알림 받기');

  const ConsentItem(this.label, {this.wireName, this.details = const []});

  /// pen 02-c 줄 글. 통합 시험(area1)이 이 글로 줄을 찾는다 — 설명은 [details] 에 따로 둔다.
  final String label;

  /// 줄 아래 늘 보이는 설명 줄(02-c 안 B). 비어 있으면 설명이 없다.
  final List<String> details;

  /// 서버 app/consents/policy.py REQUIRED_KINDS 와 같은 글자. 선택 항목은 null.
  final String? wireName;

  bool get isRequired => wireName != null;

  /// "보기"로 여는 노션 페이지(consent_links.dart). 마케팅은 보기가 없다.
  Uri? get link => switch (this) {
        ConsentItem.terms => termsLink,
        ConsentItem.privacy => privacyItemsLink,
        ConsentItem.marketing => null,
      };
}
