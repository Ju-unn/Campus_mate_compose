"""E2E 진행 프로그램. 저장소 루트에서 `python -m e2e <명령>`.

  list [접두어|묶음]      시나리오 md 의 가설 번호 · 기기 · 방식(`list area1` = 묶음 목록)
  preflight             e2e.env 키 · 실사용자 0 · signup_blocks 시작 스냅샷 · 기기 연결 · adb reverse 확인
  run 번호|묶음…          가설을 하나씩 돌려 results.jsonl 에 적는다(첫 실패는 한 번 다시). API 가설은 진행만, 폰 가설은 앱을 한 번 켤 때 하나
  report                가설마다 마지막 결과로 보고서.md
  cleanup               `+e2e` 계정 · 파일 · 시험이 만든 재가입 제한 뒷정리(KEEP 제외, 실사용자가 보이면 멈춤)
"""

import argparse
import subprocess
import sys
from collections import Counter
from pathlib import Path

from e2e import area1, area2, area3
from e2e import area1_b2  # noqa: F401 — 묶음 2 가설을 area1.PHONE · CASES · BUNDLES 에 더한다
from e2e.tools import (DEVICE_PORT, DEVICES, ROOT, Hub, Run, adb, cleanup, ensure_no_real_users, env, latest, scenario_rows,
                       serial, service_key, snapshot_blocks, verdict)

ENV_KEYS = ('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'API_BASE_URL', 'E2E_MAIL_BASE')
DESKTOP = next(p for p in (Path.home() / 'OneDrive' / 'Desktop', Path.home() / 'Desktop') if p.exists())
SCENARIO = DESKTOP / 'E2E_최종테스트_시나리오.md'
RESULTS = DESKTOP / 'E2E_결과'
BUNDLES = {**area1.BUNDLES, **area2.BUNDLES, **area3.BUNDLES}  # 묶음 이름 → 가설 번호들
API_CASES = {**{c: area1 for c in area1.CASES}, **{c: area2 for c in area2.CASES}, **{c: area3 for c in area3.CASES}}  # API 가설 → 그것을 가진 모듈


def _run(args):
    build = args.build or subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], cwd=ROOT, capture_output=True, text=True).stdout.strip()
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
    attached = subprocess.run(['adb', 'devices'], capture_output=True, text=True).stdout
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


def cmd_run(args):
    cfg, run = env(), _run(args)
    run.cfg = cfg
    phone = {}  # 폰 가설이 처음 나올 때 기기 · 우편함을 연다 — API 묶음만 돌릴 땐 폰이 없어도 된다

    def once(case):
        if (case in API_CASES or case in area1.PHONE) and not run.key:
            run.key = service_key()  # preflight 를 건너뛰어도 운영 쓰기 전에 한 번 더 본다
            ensure_no_real_users(cfg, run.key, RESULTS)
        if case in area2.SKIPPED:
            return 'skip', area2.SKIPPED[case]
        if case in API_CASES:
            return API_CASES[case].attempt(run, case)
        if not phone:
            sn, pc_port = serial(args.device, cfg), DEVICES[args.device]
            if not sn:
                sys.exit(f'e2e.env 에 E2E_DEVICE_{args.device} 가 없다')
            adb(sn, 'reverse', f'tcp:{DEVICE_PORT}', f'tcp:{pc_port}')
            phone.update(sn=sn, hub=Hub(pc_port))
        if case in area1.PHONE:
            return area1.attempt_phone(run, case, area1.Phone(run, phone['hub'], phone['sn'], case))
        return verdict(run.phone(phone['hub'], phone['sn'], {'case': case}))

    try:
        for case in [c for name in args.case for c in BUNDLES.get(name, [name])]:
            for attempt in (1, 2):
                result, note = once(case)
                if result != 'fail':
                    break
            print(run.record(case, result, f'{note} (시도 {attempt})'.lstrip()))
    finally:
        if phone:
            phone['hub'].close()


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
    return parser


def main():
    # 윈도 콘솔 기본 인코딩(cp949)은 시나리오의 '○' 같은 글자에서 print 가 터진다.
    sys.stdout.reconfigure(encoding='utf-8')
    args = build_parser().parse_args()
    globals()[f'cmd_{args.command}'](args)


if __name__ == '__main__':
    main()
