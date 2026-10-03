import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 아이콘 토큰 (DESIGN.md §5.3 Lucide 이름 매핑). 위젯은 `LucideIcons.*` 를
/// 직접 부르지 않고 이 상수만 읽는다. 표에 없는 아이콘은 쓰기 전에 표에 추가한다.
abstract final class AppIcons {
  static const IconData house = LucideIcons.house;
  static const IconData heart = LucideIcons.heart;
  static const IconData messageCircle = LucideIcons.messageCircle;
  static const IconData userRound = LucideIcons.userRound;
  static const IconData x = LucideIcons.x;
  static const IconData badgeCheck = LucideIcons.badgeCheck;
  static const IconData graduationCap = LucideIcons.graduationCap;
  static const IconData mail = LucideIcons.mail;
  static const IconData send = LucideIcons.send;
  static const IconData userPlus = LucideIcons.userPlus;
  static const IconData pause = LucideIcons.pause;
  static const IconData flag = LucideIcons.flag;
  static const IconData userX = LucideIcons.userX;

  /// 14c 하단 "차단하기" 링크(pen `divm8`)
  static const IconData ban = LucideIcons.ban;

  /// 채팅방 ⋯ 시트 "채팅방 나가기"(pen `DLfZV`)
  static const IconData logOut = LucideIcons.logOut;
  static const IconData settings = LucideIcons.settings;
  static const IconData bell = LucideIcons.bell;

  /// 11b 알림 안내 상자(pen `iQZoa`) — 켜져 있는 알림이라 `bell` 과 그림이 다르다
  static const IconData bellRing = LucideIcons.bellRing;

  /// 14f 남은 시간 상자(pen `p0XJA6`). `timer` 는 시안이 쓰지 않는 모래시계 쪽이다
  static const IconData clock3 = LucideIcons.clock3;
  static const IconData arrowLeft = LucideIcons.arrowLeft;
  static const IconData ellipsis = LucideIcons.ellipsis;
  static const IconData camera = LucideIcons.camera;
  static const IconData creditCard = LucideIcons.creditCard;
  static const IconData lock = LucideIcons.lock;
  static const IconData users = LucideIcons.users;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData chevronDown = LucideIcons.chevronDown;
  static const IconData chevronUp = LucideIcons.chevronUp;
  static const IconData circleQuestionMark = LucideIcons.circleQuestionMark;
  static const IconData star = LucideIcons.star;
  static const IconData check = LucideIcons.check;
  static const IconData arrowRight = LucideIcons.arrowRight;
  static const IconData imagePlus = LucideIcons.imagePlus;
  static const IconData plus = LucideIcons.plus;
  static const IconData timer = LucideIcons.timer;
  static const IconData shieldCheck = LucideIcons.shieldCheck;
  static const IconData phone = LucideIcons.phone;
  static const IconData contactRound = LucideIcons.contactRound;

  /// 신뢰 확인 후 카카오톡 아이디 복사 (화면 14b `MAn9h` 의 `FZqNL`)
  static const IconData copy = LucideIcons.copy;
  static const IconData trash2 = LucideIcons.trash2;

  /// 8d 연락처 검색칸 (pen SearchField `y7Qlw` 의 돋보기 `r2d1a` — pen 에 아이콘 이름이 비어 있어 모양으로 고름)
  static const IconData search = LucideIcons.search;

  /// 초안 만들기 단계 표시 (DESIGN.md §5.3 — 끝난 단계 / 하는 중 / 기다리는 중)
  static const IconData circleCheck = LucideIcons.circleCheck;
  static const IconData circleDot = LucideIcons.circleDot;
  static const IconData circle = LucideIcons.circle;

  /// 안내 카드 머리말·입력칸 오류 (DESIGN.md §5.3)
  static const IconData circleAlert = LucideIcons.circleAlert;
  /// 20c · 14d 지인 리뷰 안내 상자(pen `PMMX8` · `z5kJa6`) · 15-6 닉네임 helper(`G1tl8`) — circle-alert(느낌표)와 그림이 다르다
  static const IconData info = LucideIcons.info;

  /// 3b 인증 거절 배너 (pen Alert 마스터 `teNRJ`)
  static const IconData circleX = LucideIcons.circleX;

  /// 04-2 얼굴 없음 토스트 (pen `EvcRf`)
  static const IconData alertTriangle = LucideIcons.alertTriangle;

  /// 공개 범위 안내 (DESIGN.md 화면 3c — "카드와 프로필에 공개돼요")
  static const IconData eye = LucideIcons.eye;

  /// 20 추천 코드 "마지막 단계" 배지 (pen `h1CMd`)
  static const IconData sparkles = LucideIcons.sparkles;

  /// 화면 15 "내 키" Facts 행·"선호 키 범위" 행 (pen `K31sZl` · `Te5KQ`)
  static const IconData ruler = LucideIcons.ruler;

  /// 화면 15 "선호 나이 범위" 행 (pen `vFPb8`)
  static const IconData calendar = LucideIcons.calendar;

  /// 화면 16e "가입일" 행 (pen `nntyt`)
  static const IconData calendarCheck = LucideIcons.calendarCheck;

  /// 화면 15 "MBTI" Facts 행 (pen `Wb0JO`)
  static const IconData badge = LucideIcons.badge;

  /// 화면 15 "자기소개 · 태그" 입구 행 (pen `m2szef`)
  static const IconData tags = LucideIcons.tags;

  /// 18a 무료로 하트 모으기 줄 아이콘(pen R99dx `Fwoqx`) · 16 설정 행(`JWxQo`).
  static const IconData megaphone = LucideIcons.megaphone;
  static const IconData share2 = LucideIcons.share2;
  static const IconData vote = LucideIcons.vote;
  static const IconData gift = LucideIcons.gift;

  /// 화면 15 "프로필 편집" 입구 행 (pen `sC8BR`)
  static const IconData pencil = LucideIcons.pencil;

  /// 화면 15 지인 리뷰 칸 — "친구들이 본 나" (pen `o9BA0/GAMlp`) · "내가 쓴 리뷰" (pen `tStBN/GAMlp`)
  static const IconData heartHandshake = LucideIcons.heartHandshake;
  static const IconData messageSquareText = LucideIcons.messageSquareText;
}

/// 3D 그림 아이콘 (2026-10-01 디자인 개편 — pen 라이브러리 `Z54et > fIXLw 3D Icon Library`, 괄호 안은 타일 id).
/// 그림은 `assets/icons/` 의 designMaterialsCompact WebP(512px)이고, 화면은 [Icon3d] 로 크기만 정해 그린다.
/// pen 이 쓰지 않는 그림(아이콘 시트 · 옛 마스코트 · 옛 MBTI 등)은 넣지 않았다. 새 그림은 파일과 이 표를 같이 늘린다.
enum AppIcon3d {
  /// 학생 인증 `Trtii`
  badgeCheck('ui-3d-badge-check'),
  /// 금지 `eUCJv`
  ban('ui-3d-ban'),
  /// 알림 `WyOg1`
  bell('ui-3d-bell'),
  /// 차단 `K7lHf`
  blockUser('ui-3d-block-user'),
  /// 가입일 `UCEwf`
  calendarCheck('ui-3d-calendar-check'),
  /// 일정 `H62oC`
  calendar('ui-3d-calendar'),
  /// 시간 `oq6tX`
  clock('ui-3d-clock'),
  /// 연락처 `gTMRB`
  contact('ui-3d-contact'),
  /// 도움말 `Rb8A3`
  help('ui-3d-faq'),
  /// 선물 `e7HetT`
  gift('ui-3d-gift'),
  /// 학교 `E5TUHj`
  graduationCap('ui-3d-graduation-cap'),
  /// 친구 리뷰 `dAIki`
  heartHandshake('ui-3d-heart-handshake'),
  /// 하트 `zxXQG`
  heart('ui-3d-heart'),
  /// 안내 · 파란 느낌표 `s3b4k`
  infoBlue('ui-3d-info-blue'),
  /// 카드 도착 `wAQtn`
  layers('ui-3d-layers'),
  /// 로그아웃 `JdzhL`
  logout('ui-3d-logout'),
  /// 이메일 `m1RJR`
  mail('ui-3d-mail'),
  /// 마스코트 미리 보기 `t9q0v`
  mascotPeek('ui-3d-mascot-peek-closeup'),
  /// MBTI `MMIpS`
  mbti('ui-3d-mbti-v2'),
  /// 공지 `d7e1q`
  megaphone('ui-3d-megaphone'),
  /// 방해 금지 `I58co`
  moon('ui-3d-moon'),
  /// 편집 `DAILv`
  pencil('ui-3d-pencil'),
  /// 전화 `zsmST`
  phone('ui-3d-phone'),
  /// 개인정보 `BxTWT`
  privacy('ui-3d-privacy'),
  /// 키 `pIUSe`
  ruler('ui-3d-ruler'),
  /// 검색 `QU7qi`
  search('ui-3d-search'),
  /// 공유 `n40Hd`
  share('ui-3d-share'),
  /// 신고 사이렌 `jsi9g`
  siren('ui-3d-siren'),
  /// 반짝임 `ulHL7`
  sparkles('ui-3d-sparkles'),
  /// 태그 `aSyRM`
  tags('ui-3d-tags'),
  /// 약관 `vUQsU`
  terms('ui-3d-terms'),
  /// 삭제 `e2af0`
  trash('ui-3d-trash'),
  /// 이미지 첨부 `CR3C7`
  upload('ui-3d-upload'),
  /// 프로필 `PkqpC`
  userRound('ui-3d-user-round'),
  /// 사용자 `U17hk`
  users('ui-3d-users'),
  /// 투표 `x5QLa`
  vote('ui-3d-vote'),
  /// 대화 `Lua1H`
  chat('feature-icon-chat-3d-tight'),
  /// 홈 통계 · 가입(라이브러리 밖)
  join('feature-icon-join-neutral-3d'),
  /// 홈 통계 · 보냄(라이브러리 밖)
  send('feature-icon-send-3d'),
  /// 별점(라이브러리 밖)
  star('feature-icon-star-3d');

  const AppIcon3d(this._file);

  final String _file;

  String get asset => 'assets/icons/$_file.webp';
}
