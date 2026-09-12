# GRAPHIFY.md — 코드베이스 탐색 규칙

**코드베이스를 뒤지기 전에 지식 그래프를 먼저 조회한다.** Grep·Read 로 파일을 훑는 것은 그래프가 답을 못 줄 때만 한다.

`/graphify` 는 저장소 전체(`frontend/`·`backend/`·`docs/`)를 하나의 지식 그래프(`graphify-out/`)로 만든다.
Dart 클래스·함수·import, SQL 마이그레이션, 설계 문서(.md)가 모두 노드로 들어가고, 문서 ↔ 코드 관계까지 연결된다.

| 항목 | 값 |
| --- | --- |
| 그래프 루트 | 저장소 루트 (`campus_mate_compose/`) |
| 산출물 | `graphify-out/` — **`.gitignore` 대상.** 각 PC 에서 빌드한다 |
| 실행 | `python -m graphify <명령>` (PATH 에 `graphify` 스크립트가 없다) |
| 스킬 | `~/.claude/skills/graphify` v0.9.58, 패키지 `graphifyy` |

---

## 1. 언제 조회하는가

아래 상황이면 **먼저 그래프에 묻는다.**

- "X 는 어디서 쓰이나", "Y 를 바꾸면 무엇이 영향받나", "A 에서 B 까지 흐름"
- 새 작업을 시작할 때 — 건드릴 기능 패키지와 관련 문서를 먼저 파악
- 설계 문서와 코드의 대응을 찾을 때 (예: 스펙 §7 엔드포인트 ↔ 화면)

그래프가 "관련 노드 없음" 이라고 답하면 그때 Grep·Read 로 넘어간다.

## 2. 조회 명령

```bash
python -m graphify query "<질문>"              # BFS — 주변 맥락 넓게
python -m graphify query "<질문>" --dfs        # DFS — 특정 경로 추적
python -m graphify path "<노드A>" "<노드B>"     # 두 개념 사이 최단 경로
python -m graphify explain "<노드>"             # 한 노드의 연결 관계 설명
```

- 질문은 **그래프 어휘로 확장한 뒤** 던진다 (스킬 `references/query.md` Step 0). 리터럴 매칭이라 동의어·한↔영 번역이 안 된다
- 답은 **그래프에 있는 것만으로** 쓴다. `source_location` 을 인용한다. 그래프에 없으면 없다고 말한다

## 3. 세션 시작 시

```bash
python -m graphify reflect --if-stale
```

그리고 `graphify-out/reflections/LESSONS.md` 를 읽는다 — 이전 세션이 남긴 **선호 출처·막다른 길·정정** 이 있다.
그래프가 없으면(`graphify-out/graph.json` 부재) `/graphify .` 로 먼저 빌드한다.

## 4. 조회 결과 저장 (자기 개선 루프)

답을 쓴 뒤 그래프에 되돌려 넣는다. 다음 `--update` 때 Q&A 가 노드가 된다.

```bash
python -m graphify save-result --question "<원 질문>" --answer "<답>" --type query --nodes <노드1> <노드2> --outcome useful
```

`--outcome` 은 `useful` / `dead_end` / `corrected`(+ `--correction "<정답>"`).

## 5. 갱신 — 그래프가 낡으면 오답을 낸다

| 상황 | 누가 | 방법 |
| --- | --- | --- |
| 코드(.dart/.sql/.kt 등) 커밋 | **post-commit hook 자동** | 커밋 직후 변경 파일만 AST 재추출. LLM 비용 없음 |
| 문서(.md/.yaml) 변경 | **Claude 가 직접** | 문서를 수정한 작업 끝에 `/graphify . --update` 실행. hook 은 문서를 무시한다 |
| 패키지 구조 대규모 변경 | Claude | `/graphify . --cluster-only` 로 커뮤니티 재계산 |
| 그래프가 이상하거나 손상 | Claude | `graphify-out/` 삭제 후 `/graphify .` 재빌드 |

hook 은 `.git/hooks/post-commit` 에 들어가므로 **저장소에 포함되지 않는다.** 새로 clone 하면 다시 설치한다.

```bash
python -m graphify hook install     # 설치
python -m graphify hook status      # 확인
```

## 6. 다른 PC 에서

```bash
pip install graphifyy               # 패키지
python -m graphify install --platform claude   # 스킬 (~/.claude/skills/graphify)
python -m graphify hook install     # 커밋 hook
/graphify .                         # 첫 빌드 (저장소 루트에서)
```

## 7. 하지 않는 것

- `graphify-out/` 을 커밋하지 않는다 (공개 저장소에 아키텍처 그래프를 노출할 이유가 없다)
- 그래프에 없는 관계를 추측해서 답하지 않는다
- 문서를 고치고 `--update` 를 빼먹지 않는다 — 다음 세션이 낡은 그래프를 믿게 된다
