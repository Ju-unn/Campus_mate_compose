import 'package:campus_mate/core/theme/app_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  test('DESIGN.md §5.3 화면별 이름은 같은 이름의 Lucide 아이콘을 쓴다', () {
    expect(AppIcons.house, LucideIcons.house);
    expect(AppIcons.heart, LucideIcons.heart);
    expect(AppIcons.messageCircle, LucideIcons.messageCircle);
    expect(AppIcons.userRound, LucideIcons.userRound);
    expect(AppIcons.x, LucideIcons.x);
    expect(AppIcons.badgeCheck, LucideIcons.badgeCheck);
    expect(AppIcons.graduationCap, LucideIcons.graduationCap);
    expect(AppIcons.mail, LucideIcons.mail);
    expect(AppIcons.send, LucideIcons.send);
    expect(AppIcons.userPlus, LucideIcons.userPlus);
    expect(AppIcons.pause, LucideIcons.pause);
    expect(AppIcons.flag, LucideIcons.flag);
    expect(AppIcons.userX, LucideIcons.userX);
    expect(AppIcons.settings, LucideIcons.settings);
    expect(AppIcons.bell, LucideIcons.bell);
    expect(AppIcons.arrowLeft, LucideIcons.arrowLeft);
    expect(AppIcons.ellipsis, LucideIcons.ellipsis);
    expect(AppIcons.camera, LucideIcons.camera);
    expect(AppIcons.creditCard, LucideIcons.creditCard);
    expect(AppIcons.lock, LucideIcons.lock);
    expect(AppIcons.users, LucideIcons.users);
    expect(AppIcons.chevronRight, LucideIcons.chevronRight);
    expect(AppIcons.check, LucideIcons.check);
    expect(AppIcons.arrowRight, LucideIcons.arrowRight);
    expect(AppIcons.imagePlus, LucideIcons.imagePlus);
    expect(AppIcons.timer, LucideIcons.timer);
    expect(AppIcons.shieldCheck, LucideIcons.shieldCheck);
    expect(AppIcons.phone, LucideIcons.phone);
    expect(AppIcons.contactRound, LucideIcons.contactRound);
    expect(AppIcons.trash2, LucideIcons.trash2);
    expect(AppIcons.eye, LucideIcons.eye);
  });
}
