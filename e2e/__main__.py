"""E2E 진행 프로그램. 저장소 루트에서 `python -m e2e <명령>`.

  list [접두어|묶음]      시나리오 md 의 가설 번호 · 기기 · 방식(`list area1` = 묶음 목록)
  preflight             e2e.env 키 · 실사용자 0 · signup_blocks 시작 스냅샷 · 기기 연결 · adb reverse 확인
  run 번호|묶음…          가설을 하나씩 돌려 results.jsonl 에 적는다(첫 실패는 한 번 다시). API 가설은 진행만, 폰 가설은 앱을 한 번 켤 때 하나
  report                가설마다 마지막 결과로 보고서.md
  cleanup               `+e2e` 계정 · 파일 · 시험이 만든 재가입 제한 뒷정리(KEEP 제외, 실사용자가 보이면 멈춤)
  photos                E2E_결과/사진/ 에 사진 세트(묶음 3) 파일이 다 있는지 — 없는 이름을 알려 준다
"""

import argparse
import subprocess
import sys
from collections import Counter
from pathlib import Path

from e2e import area1, area2, area3, area3_safe, area5_api, tools, twodev
from e2e import area1_b2  # noqa: F401 — 묶음 2 가설을 area1.PHONE · CASES · BUNDLES 에 더한다
from e2e import area3_phone  # noqa: F401 — 영역 3 폰 1차 가설을 area1.PHONE · area3.BUNDLES 에 더한다
from e2e import area3_phone2  # noqa: F401 — 영역 3 폰 2차(입력 · 보내기 · 신고 · 수락 · 시트) 가설을 같은 곳에 더한다
from e2e import area3_phone3  # noqa: F401 — 영역 3 폰 3차(꺼진 앱에서 알림 눌러 방 열기) 가설을 같은 곳에 더한다
from e2e import area3_phone4  # noqa: F401 — 영역 3 폰 4차(매칭 시각을 옮긴 방의 14f 시트) 가설을 같은 곳에 더한다
from e2e import area3_phone5  # noqa: F401 — 영역 3 배치(chat-gate · cleanup 을 실제로 부르는) 가설 — 폰 8개는 area1.PHONE 에, API 1개는 아래 API_CASES 에 더한다
from e2e import area3_phone6  # noqa: F401 — 영역 3 E-CHAT-53(07시대 · 08시대 chat-gate 를 한 실행에서 두 번) 폰 가설을 area1.PHONE · area3.BUNDLES 에 더한다
from e2e import area3_safe_phone  # noqa: F401 — 영역 3 안전 폰(신고 · 차단 · 정지) 가설을 같은 곳에 더한다
from e2e import area1_b3  # 묶음 3(사진 세트) — 같은 방식
from e2e import area1_b4  # noqa: F401 — 묶음 4(아바타) — 같은 방식
from e2e import area1_b5  # noqa: F401 — 묶음 5(검토 이후 · 재부팅 · 식은 서버) — 같은 방식
from e2e import area1_b6  # noqa: F401 — 묶음 6(두 기기 · 에뮬 네트워크) — 같은 방식
from e2e import area1_emu  # noqa: F401 — B에뮬 가설(네트워크 · 시계 · 브라우저)
from e2e import area2_emu_home  # noqa: F401 — 영역 2 에뮬 홈 가설 7(대기 화면 · 초대 공유 창 · 글자 확대)
from e2e import emu
from e2e import area4  # noqa: F401 — 영역 4 가설을 같은 곳에 더한다
from e2e import area2_phone  # noqa: F401 — 영역 2 폰 A 가설을 area1.PHONE · BUNDLES 에 더한다
from e2e import area2_phone_b  # noqa: F401 — 영역 2 폰 A 2차 가설을 더한다
from e2e import area4_set2  # noqa: F401 — 영역 4 설정 2차(FAQ · 초대 · 로그아웃 · 탈퇴)
from e2e import area4_extra  # noqa: F401 — 영역 4 미등록 가설 10개 (E-HEART 46·49·51, E-SET 04·12·26·43·52·53·67)
from e2e import area4_push_a4  # noqa: F401 — 영역 4 알림 A4(토큰 · 권한 · 로그인/로그아웃)
from e2e import area4_push_gate  # noqa: F401 — 영역 4 알림 채팅 게이트 배치(리마인드 · 닫기, chat-gate)
from e2e import area2_phone3  # noqa: F401 — 영역 2 폰 A 3차(망 끊기 · 카드 · 알림 · 공유 창 · 하트 다시 만들기) 가설
from e2e import area5_read  # noqa: F401 — 영역 5 폰 A 화면 읽기(나 탭 · 탈퇴 · 시스템 뒤로) 가설을 같은 곳에 더한다
from e2e import area5_act  # noqa: F401 — 영역 5 폰 A 고쳐 저장하기(글 · 태그 · 조건 · 기본 정보) 가설을 같은 곳에 더한다
from e2e import area5_photo  # noqa: F401 — 영역 5 폰 A 아바타 다시 만들기 · 15-7 사진 수정 8개를 같은 곳에 더한다
from e2e import area5_wd  # noqa: F401 — 영역 5 폰 A 탈퇴 흐름 9개(일시중지 · 영구 삭제 · 재가입 제한 · 정리 배치 · 강제 종료)를 같은 곳에 더한다(E-WD-12 는 API)
from e2e import area5_edge  # noqa: F401 — 영역 5 경계 7개(폰 A: E-EDGE-01 · 11 · 15 · 19, B에뮬: 21 · 24 · 25)를 area1.PHONE · BUNDLES 에 더한다
from e2e import area5_new  # noqa: F401 — 영역 5 새 5개(폰 A: E-EDGE-12 · E-WD-19, B에뮬: E-EDGE-04 · E-WD-20 · E-EDGE-10)를 area1.PHONE · BUNDLES 에 더한다
from e2e import area5_two  # noqa: F401 — 영역 5 두 기기 탈퇴 5개(E-WD-05 ~ 09)를 twodev.TWO · area1.BUNDLES 에 더한다
from e2e import area5_time  # noqa: F401 — 영역 5 시간조작 2개(E-WD-10 게이트 미통과 방 · E-WD-11 30일 정리 배치)를 area1.PHONE · BUNDLES 에 더한다
from e2e import area2_time_device  # noqa: F401 — 영역 2 기기 · 시각 가설 13(배치 + 알림 · 시계)
from e2e import area4_contacts  # noqa: F401 — 영역 4 연락처(B에뮬)
from e2e import area3_contacts  # noqa: F401 — 영역 3 연락처 차단(B에뮬)
from e2e import area2_time_batch  # 영역 2 배치 가설(daily-cards · cleanup 을 불러 PC 에서 DB · API 로 읽음)
from e2e import area2_time_api  # 영역 2 시간 API(배치 없이 DB 시각만 옮겨 API · RPC 로 확인)
from e2e import area2_batch_admin  # 영역 2 배치 운영(E-BATCH-01~03) — 스케줄러 설정 · /batch/* 신원 · 401 뒤 DB 무변화
from e2e import area2_two_poll  # noqa: F401 — 영역 2 두 기기 투표 글 가설 8(twodev.TWO · area1.BUNDLES 에 더한다)
from e2e import area2_two_accept  # noqa: F401 — 영역 2 두 기기 카드 수락(일시중지 · 거절 · 매칭 · 연타 · 이미 매칭된 사람) 가설을 twodev.TWO · area1.BUNDLES 에 더한다
from e2e import area4_push_two  # noqa: F401 — 영역 4 알림 두 기기(E-PUSH-64 · 65 · 71) 가설을 twodev.TWO · area1.BUNDLES 에 더한다
from e2e import area4_set56  # noqa: F401 — 영역 4 E-SET-56(약관 줄) 가설을 area1.PHONE · BUNDLES 에 더한다
from e2e import area5_more  # noqa: F401 — 영역 5 E-ME-05 · 22 · 32 가설을 area1.PHONE · twodev.TWO · area1.BUNDLES 에 더한다
from e2e import area5_fake  # noqa: F401 — 영역 5 가짜 서버 응답 E-EDGE-05 · 06 · 07 · 08 을 area1.PHONE · BUNDLES 에 더한다
from e2e import area5_kill  # noqa: F401 — 영역 5 아바타 만드는 중 앱 죽이기 E-EDGE-17 · 18 을 area1.PHONE · BUNDLES 에 더한다
from e2e import area2_emu_b  # noqa: F401 — 영역 2 B에뮬 가설 11(수락함 · 투표 · 추천 코드)
from e2e import area4_push_front  # noqa: F401 — 영역 4 알림 A3(앱이 앞에 있을 때)
from e2e import area4_push_tap  # noqa: F401 — 영역 4 알림 A2(알림을 눌러 화면 열기)
from e2e import area4_push  # noqa: F401 — 영역 4 알림 A1(받는 사람 폰 + 상대 API, 알림 읽기)
from e2e import area4_push_night  # noqa: F401 — 영역 4 알림 밤·아침·시각 경계(밤 1단계 + 아침 2단계)
from e2e import area3_phone7  # noqa: F401 — 영역 3 밤 가설 E-CHAT-34 · 42 · E-REV-18 을 영역 4 밤 판(E-PUSH-33 · 86 · 52)의 별칭으로 area1.PHONE · area3.BUNDLES 에 더한다(area4_push_night 뒤에)
from e2e import area3_phone8  # noqa: F401 — 영역 3 폰 A 한 대 8차 — 채팅 · 지인 리뷰 E-CHAT-10 · 16 · E-REV-20 · 24 · 27 · 31 · 34 · 35 + E-CHAT-68 API
from e2e import area3_chat_nt  # noqa: F401 — 영역 3 알림 10개 E-CHAT-17 · 26 · 27 · 28 · 29 · 30 · 31 · 33 · 35 · 59 (단일 폰 + 상대 API, 묶음 area3-chat-nt)
from e2e import area3_chat_rt  # noqa: F401 — 영역 3 실시간 · 화면 — 폰 한 대 E-CHAT-01 · 02 · 07 · 22 · 23 · 24 · 61 · 72 + 두 기기 E-CHAT-03 · 58(twodev.TWO · area1.BUNDLES 에도 더한다)
from e2e import area3_phone11  # noqa: F401 — 영역 3 신뢰 확인 E-CHAT-37 · 38 · 40 · 41(폰 한 대) + 39 · 44(폰 + 에뮬 두 기기, 묶음 area3-two-11)
from e2e import area3_phone9  # noqa: F401 — 영역 3 지인 리뷰 알림 E-REV-16 · 17 · 26(단일 폰, area1.PHONE · area3.BUNDLES) · E-REV-41(두 기기, twodev.TWO)
from e2e import area4_push_card  # noqa: F401 — 영역 4 알림 카드 배치 9(E-PUSH-01~09, daily-cards 를 불러 알림이 오는지 · 안 오는지)
from e2e import area3_batch  # noqa: F401 — 영역 3 배치 E-BATCH-14~17 · 22 · 23 을 기존 판(E-PUSH-40 · 46 · 44 · 47 · E-AUTH-12 · E-HEART-22)의 별칭으로 area1.PHONE · area3.BUNDLES 에 더한다(API 둘은 아래 API_CASES)
from e2e import area2_aliases  # 영역 2 별칭 9개(E-CARD-40 · 43 · 46 · 48, E-BATCH-05~09) — 원본(area2_time_device · area4_push · area2_time_batch) 뒤에
from e2e import area2_ref06  # noqa: F401 — 영역 2 E-REF-06(새 사람이 가입 마지막에 추천 코드 · 단일 폰, 앱은 E-ONB-60 과 같다)을 area1.PHONE · BUNDLES 에 더한다(area1_b2 뒤에)
from e2e.tools import (DEVICE_PORT, DEVICES, ROOT, TEXT, Hub, Run, adb, cleanup, ensure_no_real_users, env, latest, scenario_rows,
                       serial, service_key, snapshot_blocks, verdict)

ENV_KEYS = ('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'API_BASE_URL', 'E2E_MAIL_BASE')
DESKTOP = next(p for p in (Path.home() / 'OneDrive' / 'Desktop', Path.home() / 'Desktop') if p.exists())
SCENARIO = DESKTOP / 'CampusMate_문서' / 'E2E' / 'E2E_최종테스트_시나리오.md'
RESULTS = DESKTOP / 'E2E_결과'
BUNDLES = {**area1.BUNDLES, **area2.BUNDLES, **area3.BUNDLES, **area3_safe.BUNDLES, **area5_api.BUNDLES,
           **area2_time_api.BUNDLES,
           **area2_time_batch.BUNDLES,
           **area2_batch_admin.BUNDLES,
           **area2_aliases.BUNDLES}  # 묶음 이름 → 가설 번호들
API_CASES = {**{c: area1 for c in area1.CASES}, **{c: area2 for c in area2.CASES}, **{c: area3 for c in area3.CASES},
             **{c: area3_safe for c in area3_safe.CASES}, **{c: area5_api for c in area5_api.CASES},
             **{c: area2_time_api for c in area2_time_api.CASES},
             **{c: area2_time_batch for c in area2_time_batch.CASES},
             **{c: area2_batch_admin for c in area2_batch_admin.CASES},
             **{c: area2_aliases for c in area2_aliases.CASES}}  # API 가설 → 그것을 가진 모듈
API_CASES.update({c: area3_phone5 for c in area3_phone5.CASES})  # E-CHAT-69(정리 배치 · 폰 없음) — area3.CASES 에 안 넣어 area3-api 묶음이 그대로다
API_CASES.update({c: area3_batch for c in area3_batch.CASES})  # E-BATCH-22 · 23(기존 API 판의 별칭)
API_CASES.update({c: area3_phone8 for c in area3_phone8.CASES})


def _run(args):
    build = args.build or subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], cwd=ROOT, **TEXT).stdout.strip()
    return Run(RESULTS / args.bundle, build, args.revision)


def cmd_list(args):
    rows = scenario_rows(SCENARIO.read_text(encoding='utf-8'))
    bundles = [b for b in BUNDLES if args.prefix and b.startswith(args.prefix)]
    if not bundles:
        for row in rows:
            if row['case'].startswith(args.prefix):
                print(f"{row['case']}\t{row['device']}\t{row['method']}")
        return
    by_case = {r['case']: r for r in rows}
    for bundle in bundles:
        print(f'# {bundle}')
        for case in BUNDLES[bundle]:
            row = by_case.get(case, {})
            print(f"{case}\t{row.get('device', '시나리오에 없음')}\t{row.get('method', '')}")
        for case, reason in (area2.SKIPPED if bundle in area2.BUNDLES else {}).items():
            print(f'{case}\t빠짐\t{reason}')


def cmd_preflight(args):
    ok = True
    cfg = env()
    missing = [k for k in ENV_KEYS if not cfg.get(k)]
    if missing:
        ok = False
        print(f'e2e.env 에 없음: {", ".join(missing)}')
    attached = tools.devices()
    for name in args.device:
        sn, pc_port = serial(name, cfg), DEVICES[name]
        if not sn:
            ok = False
            print(f'{name}: e2e.env 에 E2E_DEVICE_{name} 없음')
            continue
        if f'{sn}\tdevice' not in attached:
            ok = False
            print(f'{name} 연결 안 됨')
            continue
        adb(sn, 'reverse', f'tcp:{DEVICE_PORT}', f'tcp:{pc_port}')
        print(f'{name} 연결 · reverse {DEVICE_PORT}→{pc_port}')
    if not missing:
        # 운영 쓰기 전 마지막 문 — 시험 계정 · KEEP 말고 한 명이라도 있으면 돌리지 않는다(설계 2절 안전).
        key = service_key()
        print(f'실사용자 {ensure_no_real_users(cfg, key, RESULTS)}명')  # 있으면 여기서 멈춘다
        snapshot_blocks(cfg, key, RESULTS)
    sys.exit(0 if ok else 1)


def case_limit(case, phone_case):
    """가설 하나에 줄 시간(초). 기기를 만지는 가설만 건다 — 서버 API 묶음은 그대로."""
    return tools.CASE_LIMITS.get(case, tools.CASE_LIMIT) if phone_case else None


def _seen(where):
    """시간 초과 때 기기에 보이던 것 — 못 읽어도 시간 초과 메모는 그대로."""
    if not where:
        return ''
    try:
        return f' — 지금 보이는 것: {where()}'
    except Exception:
        return ''


def run_case(once, case, limit=None, where=None):
    """가설 하나를 돈다(fail 이면 한 번 더) → (시도 횟수, 결과, 메모). 예상 밖 예외는 그 가설만 blocked 로 — 묶음이 죽지 않는다.
    [limit] 초를 넘기면 그 가설만 blocked(시간 초과)로 끝내고 다시 하지 않는다 — [where] 가 있으면 그때 기기에 보이던 것을 메모에 적는다.
    Ctrl-C · sys.exit 는 Exception 이 아니라 그대로 멈춘다."""
    tools.take_retries()
    attempt, result, note = 0, 'blocked', ''
    for attempt in (1, 2):
        try:
            with tools.case_deadline(limit):
                result, note = once(case)
        except tools.CaseTimeout as e:
            result, note = 'blocked', f'시간 초과 — {e}{_seen(where)}'
            break
        except Exception as e:
            result, note = 'blocked', f'진행 프로그램 예외 {type(e).__name__}: {e}'
        if result != 'fail':
            break
    paths = tools.retry_paths()
    retried = tools.take_retries()
    if retried:
        seen = ', '.join(path if n == 1 else f'{path} ×{n}' for path, n in Counter(paths).items())
        text = f'통신 재시도 {retried}번' + (f': {seen}' if seen else '')
        note = f'{note} ({text})' if note else text
    return attempt, result, note


def cmd_run(args):
    cfg, run = env(), _run(args)
    run.cfg = cfg
    opened = {}  # 기기 이름 → (시리얼, 우편함). 폰 가설 · 두 기기 가설이 처음 필요할 때 연다 — API 묶음만 돌릴 땐 기기가 없어도 된다
    phone = {}  # 시간 초과 때 화면을 찍을 기기(마지막으로 연 것) — [_where] 가 읽는다

    def device(name):
        # 같은 기기는 우편함을 한 번만 연다 — 같은 포트에 둘을 열면 윈도에서 말이 갈린다
        if name not in opened:
            sn = serial(name, cfg)
            if not sn:
                sys.exit(f'e2e.env 에 E2E_DEVICE_{name} 가 없다')
            adb(sn, 'reverse', f'tcp:{DEVICE_PORT}', f'tcp:{DEVICES[name]}')
            opened[name] = (sn, Hub(DEVICES[name]))
        phone.update(sn=opened[name][0])  # 이미 연 기기를 다시 써도 "방금 쓴 기기" 가 된다
        return opened[name]

    def once(case):
        if (case in API_CASES or case in area1.PHONE or case in twodev.TWO) and not run.key:
            run.key = service_key()  # preflight 를 건너뛰어도 운영 쓰기 전에 한 번 더 본다
            ensure_no_real_users(cfg, run.key, RESULTS)
        if case in area2.SKIPPED:
            return 'skip', area2.SKIPPED[case]
        if case in API_CASES:
            return API_CASES[case].attempt(run, case)
        if case in twodev.TWO:  # 두 기기 가설은 늘 A=폰 · B=에뮬 — --device 와 상관없다
            for name in ('A', 'B'):  # 우편함을 열기 전에 시리얼부터 다 확인한다
                if not serial(name, cfg):
                    sys.exit(f'e2e.env 에 E2E_DEVICE_{name} 가 없다 (두 기기 가설은 A=폰 · B=에뮬)')
            sides = [twodev.Side(device(name)[1], device(name)[0]) for name in ('A', 'B')]
            return twodev.TWO[case](run, twodev.bound(run, case, *sides))
        sn, hub = device(args.device)
        if case in area1.PHONE:
            return area1.attempt_phone(run, case, area1.Phone(run, hub, sn, case))
        return verdict(run.phone(hub, sn, {'case': case}))

    try:
        for case in [c for name in args.case for c in BUNDLES.get(name, [name])]:
            attempt, result, note = _run_one(once, case, run, phone)
            print(run.record(case, result, f'{note} (시도 {attempt})'.lstrip()))
    finally:
        for _, hub in opened.values():
            hub.close()


def _run_one(once, case, run, phone):
    phone_case = case in area1.PHONE or case not in API_CASES
    return run_case(once, case, limit=case_limit(case, phone_case), where=lambda: _where(run, phone, case))


def _where(run, phone, case):
    """시간 초과 때 기기가 어떤 모습인지 — 화면 한 장을 shots/ 에 저장하고 맨 위 화면 이름을 돌려준다(PC 에만 둔다)."""
    if not phone:
        return '기기를 아직 안 만짐'
    shot = run.shot(phone['sn'], f'{case}-시간초과')
    top = next((line.strip() for line in tools.adb(phone['sn'], 'shell', 'dumpsys', 'activity', 'activities').splitlines()
                if 'topResumedActivity' in line or 'mResumedActivity' in line), '알 수 없음')
    return f'{top}' + (f' (화면 {shot.name})' if shot else '')


def cmd_report(args):
    run = _run(args)
    last = latest(run.records())
    counts = Counter(r['result'] for r in last.values())
    lines = [f'# E2E {args.bundle} 보고서', '', ' · '.join(f'{k} {v}' for k, v in sorted(counts.items())), '',
             '| 번호 | 결과 | 메모 | 빌드 | 서버 |', '|---|---|---|---|---|']
    lines += [f"| {c} | {r['result']} | {r['note'].replace('|', '｜')} | {r['build']} | {r['revision'] or ''} |" for c, r in sorted(last.items())]
    (run.out / '보고서.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print('\n'.join(lines[:3]))


def cmd_cleanup(args):
    cleanup(env(), service_key(), RESULTS)


def cmd_emu(args):
    """에뮬(B) 준비 점검 — 읽기만 한다. 부팅이 끝나기를 --wait 초까지 기다린다. 필수 줄이 하나라도 안 되면 종료 코드 1."""
    sn = serial(args.device, env())
    rows = emu.check(sn, wait=args.wait)
    for row in rows:
        mark = 'OK' if row.ok else ('NO' if row.hard else '--')
        print(f'[{mark}] {row.name}' + (f' — {row.detail}' if row.detail else ''))
    sys.exit(0 if all(r.ok for r in rows if r.hard) else 1)


def cmd_photos(args):
    folder = RESULTS / '사진'
    absent = area1_b3.missing(folder)
    print(f'{folder} — 사진 세트 {len(area1_b3.PHOTO_SET) - len(absent)}/{len(area1_b3.PHOTO_SET)}')
    for name in absent:
        print(f'없음: {name}')
    sys.exit(1 if absent else 0)


def build_parser():
    def common(parser, default):
        # 명령 앞(기본값을 정함) · 뒤(SUPPRESS — 안 주면 앞 값을 덮지 않음) 어디에 둬도 된다.
        parser.add_argument('--bundle', default=default or 'area1-1', help='결과 폴더 이름(바탕화면 E2E_결과/<묶음>)')
        parser.add_argument('--build', default=default, help='앱 빌드 커밋(기본: 지금 HEAD)')
        parser.add_argument('--revision', default=default, help='서버 Cloud Run revision')
        return parser

    parser = common(argparse.ArgumentParser(prog='python -m e2e'), None)
    after = common(argparse.ArgumentParser(add_help=False), argparse.SUPPRESS)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('list', parents=[after]).add_argument('prefix', nargs='?', default='')
    sub.add_parser('preflight', parents=[after]).add_argument('--device', nargs='+', default=['A'], choices=DEVICES)
    p = sub.add_parser('run', parents=[after])
    p.add_argument('case', nargs='+')
    p.add_argument('--device', default='A', choices=DEVICES)
    sub.add_parser('report', parents=[after])
    sub.add_parser('cleanup', parents=[after])
    p = sub.add_parser('emu', parents=[after])
    p.add_argument('--device', default='B', choices=DEVICES)
    p.add_argument('--wait', type=int, default=120)
    sub.add_parser('photos', parents=[after])
    return parser


def main():
    # 윈도 콘솔 기본 인코딩(cp949)은 시나리오의 '○' 같은 글자에서 print 가 터진다.
    sys.stdout.reconfigure(encoding='utf-8')
    args = build_parser().parse_args()
    globals()[f'cmd_{args.command}'](args)


if __name__ == '__main__':
    main()
