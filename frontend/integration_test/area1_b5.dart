part of 'area1.dart';

// 영역 1 묶음 5 — 재부팅. PC 쪽은 e2e/area1_b5.py 의 같은 번호.
// 학생증 검토 이후(3b 대기 화면 · 통과 · 알림) 시나리오는 2026-10-17 학생증 제거로 뺐다.

final Map<String, Area1Case> _b5Cases = {
  // 로그인 → (PC 가 재부팅) → 다시 켠 앱이 로그인 화면 없이 홈.
  'E-AUTH-18': _session((tester, job) async {
    if (job['phase'] == 'login') {
      await arrive(tester, 'home');
      return null;
    }
    return _arriveAt(tester, job);
  }),
};
