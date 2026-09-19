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
  static const IconData settings = LucideIcons.settings;
  static const IconData bell = LucideIcons.bell;
  static const IconData arrowLeft = LucideIcons.arrowLeft;
  static const IconData ellipsis = LucideIcons.ellipsis;
  static const IconData camera = LucideIcons.camera;
  static const IconData creditCard = LucideIcons.creditCard;
  static const IconData lock = LucideIcons.lock;
  static const IconData users = LucideIcons.users;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData check = LucideIcons.check;
  static const IconData arrowRight = LucideIcons.arrowRight;
  static const IconData imagePlus = LucideIcons.imagePlus;
  static const IconData timer = LucideIcons.timer;
  static const IconData shieldCheck = LucideIcons.shieldCheck;
  static const IconData phone = LucideIcons.phone;
  static const IconData contactRound = LucideIcons.contactRound;
  static const IconData trash2 = LucideIcons.trash2;

  /// 공개 범위 안내 (DESIGN.md 화면 3c — "카드와 프로필에 공개돼요")
  static const IconData eye = LucideIcons.eye;
}
