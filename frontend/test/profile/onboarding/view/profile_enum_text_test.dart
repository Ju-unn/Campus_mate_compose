import 'package:campus_mate/l10n/app_localizations_ko.dart';
import 'package:campus_mate/profile/onboarding/model/data/profile_enums.dart';
import 'package:campus_mate/profile/onboarding/view/profile_enum_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// 동물상 · 인상 · 종교 · 유입경로 칩 글자(1.0.2 B8 에서 enum 밖 문구 파일로 옮겼다). 글자는 옮기기 전 그대로다.
void main() {
  final l10n = AppLocalizationsKo();

  test('동물상 8종의 글자', () {
    expect({for (final type in AnimalType.values) type: type.label(l10n)}, {
      AnimalType.dog: '강아지상',
      AnimalType.cat: '고양이상',
      AnimalType.fox: '여우상',
      AnimalType.bear: '곰상',
      AnimalType.rabbit: '토끼상',
      AnimalType.deer: '사슴상',
      AnimalType.wolf: '늑대상',
      AnimalType.hamster: '햄스터상',
    });
  });

  test('인상 5종의 글자', () {
    expect({for (final type in ImpressionType.values) type: type.label(l10n)}, {
      ImpressionType.arab: '아랍상',
      ImpressionType.tofu: '두부상',
      ImpressionType.kind: '선한상',
      ImpressionType.chic: '시크상',
      ImpressionType.innocent: '청순상',
    });
  });

  test('종교 4종의 글자', () {
    expect({for (final religion in Religion.values) religion: religion.label(l10n)}, {
      Religion.none: '무교',
      Religion.protestant: '기독교',
      Religion.catholic: '천주교',
      Religion.buddhist: '불교',
    });
  });

  test('유입경로 칩 5개의 글자 — 서버로 가는 값은 글자가 아니라 name 이다', () {
    expect({for (final channel in AcquisitionChannel.values) channel.name: channel.label(l10n)}, {
      'everytime': '에브리타임',
      'instagram': '인스타그램',
      'friend': '친구 소개',
      'community': '커뮤니티',
      'other': '기타',
    });
  });
}
