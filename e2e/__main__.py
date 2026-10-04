"""E2E 진행 프로그램. 저장소 루트에서 `python -m e2e <명령>`.

  list [접두어]          시나리오 md 의 가설 번호 · 기기 · 방식
  preflight             e2e.env 키 · 기기 연결 · adb reverse 확인
  run 번호…              폰 가설을 앱을 한 번 켤 때 하나씩 돌려 results.jsonl 에 적는다(첫 실패는 한 번 다시)
  report                가설마다 마지막 결과로 보고서.md
  cleanup               `+e2e` 계정 뒷정리 — 계정 공장(T3)과 같이 들어온다
"""

import argparse
import subprocess
import sys
from collections import Counter
from pathlib import Path

from e2e.tools import DEVICE_PORT, DEVICES, ROOT, Hub, Run, adb, env, latest, scenario_rows, serial, verdict

ENV_KEYS = ('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'API_BASE_URL', 'E2E_MAIL_BASE')
DESKTOP = next(p for p in (Path.home() / 'OneDrive' / 'Desktop', Path.home() / 'Desktop') if p.exists())
SCENARIO = DESKTOP / 'E2E_최종테스트_시나리오.md'


def _run(args):
    build = args.build or subprocess.run(['git', 'rev-parse', '--short', 'HEAD'], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    return Run(DESKTOP / 'E2E_결과' / args.bundle, build, args.revision)


def cmd_list(args):
    for row in scenario_rows(SCENARIO.read_text(encoding='utf-8')):
        if row['case'].startswith(args.prefix):
            print(f"{row['case']}\t{row['device']}\t{row['method']}")


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
    # ponytail: 실사용자 0 확인은 서비스 키가 필요해 계정 공장(T3)과 같이 넣는다 — 그 전엔 운영 쓰기 가설을 돌리지 않는다.
    sys.exit(0 if ok else 1)


def cmd_run(args):
    sn, pc_port = serial(args.device, env()), DEVICES[args.device]
    if not sn:
        sys.exit(f'e2e.env 에 E2E_DEVICE_{args.device} 가 없다')
    adb(sn, 'reverse', f'tcp:{DEVICE_PORT}', f'tcp:{pc_port}')
    run, hub = _run(args), Hub(pc_port)
    try:
        for case in args.case:
            for attempt in (1, 2):
                result, note = verdict(run.phone(hub, sn, {'case': case}))
                if result != 'fail':
                    break
            print(run.record(case, result, f'{note} (시도 {attempt})'.lstrip()))
    finally:
        hub.close()


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
    sys.exit('cleanup 은 계정 공장(T3, e2e/area1.py)과 같이 들어온다 — 지금은 지울 계정을 만드는 코드가 없다.')


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
