import 'package:campus_mate/core/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('press 는 눌림 피드백용 120ms easeOut 이다', () {
    expect(AppMotion.press, const Duration(milliseconds: 120));
    expect(AppMotion.pressCurve, Curves.easeOut);
  });

  test('standard 는 화면 전환용 220ms easeOutCubic 이다', () {
    expect(AppMotion.standard, const Duration(milliseconds: 220));
    expect(AppMotion.standardCurve, Curves.easeOutCubic);
  });

  test('emphasis 는 매칭 성사·카드 등장용 420ms easeOutBack 이다', () {
    expect(AppMotion.emphasis, const Duration(milliseconds: 420));
    expect(AppMotion.emphasisCurve, Curves.easeOutBack);
  });

  test('float 는 대기 화면 마스코트가 한 번 떠올랐다 내려오는 1600ms easeInOut 이다(pen `tUaGw` 움직임 메모)', () {
    expect(AppMotion.float, const Duration(milliseconds: 1600));
    expect(AppMotion.floatCurve, Curves.easeInOut);
  });

  // 사용자 2026-11-16 「스낵바 … 들어올땐 east out 나갈때 ease in」 — 시간은 원문에 없어 standard 에 맞추고 사라질 때는 짧게 정했다.
  test('스낵바 · 토스트 · 팝업 · 시트는 220ms(= standard) easeOut 으로 나타나고 180ms easeIn 으로 사라진다', () {
    expect(AppMotion.appear, AppMotion.standard);
    expect(AppMotion.disappear, const Duration(milliseconds: 180));
    expect(AppMotion.appearCurve, Curves.easeOut);
    expect(AppMotion.disappearCurve, Curves.easeIn);
  });

  test('거꾸로(1→0) 도는 컨트롤러에 주는 사라짐 커브는 눈에 easeIn(천천히 떠나기 시작해 빨라짐)으로 보인다', () {
    // CurvedAnimation 은 거꾸로 돌 때도 커브를 t 그대로 읽는다. 사라짐이 τ 만큼 진행됐을 때 떠난 정도가 easeIn(τ) 여야 한다.
    for (final tau in [0.1, 0.25, 0.5, 0.75, 0.9]) {
      expect(1 - AppMotion.disappearReverseCurve.transform(1 - tau), closeTo(Curves.easeIn.transform(tau), 1e-9));
    }
  });

  test('팝업은 0.96 에서 커지고(pen 확인 팝업 값표, 대장 전달 11-16), 체크박스는 220ms easeInOut 으로 바뀐다', () {
    expect(AppMotion.popupScaleFrom, 0.96);
    expect(AppMotion.checkbox, const Duration(milliseconds: 220));
    expect(AppMotion.checkboxCurve, Curves.easeInOut);
  });
}
