# GIT.md — CampusMate Git 규칙

**git 작업(브랜치·커밋·푸시·PR)을 하기 전에 이 문서를 먼저 읽는다.**

## 0. 저장소

| 항목 | 값 |
| --- | --- |
| 저장소 | `github.com/Ju-unn/Campus_mate_compose` (단일 저장소) |
| 공개 범위 | **public** |
| 구조 | `frontend/`(Flutter 앱) · `backend/`(FastAPI, 조각 4에서 시작) · `docs/`(공통 문서) |

> ⚠️ **공개 저장소다.** 한 번 푸시하면 히스토리·캐시·크롤러에 남아 되돌리기 어렵다.
>
> - Supabase·OpenAI 키, `.env`, 키스토어를 절대 커밋하지 않는다
> - **실존 인물 사진을 커밋하지 않는다.** `frontend/assets/images/` 의 `human1/2`·`card-*`·`avatar-*`·`rail-*` 는
>   `.gitignore` 로 제외되어 있다. 이 제외 규칙을 풀지 않는다 (mock 이 필요하면 `animal-face-*` 일러스트를 쓴다)

---

## 1. 커밋 메시지 형식

**gitmoji + Conventional Commits** 를 함께 쓴다. 이모지가 맨 앞에 온다.

```
<이모지> <타입>(<scope>): <한국어 요약>

- 본문은 무엇을 왜 그렇게 했는지 (한국어)
```

예시:

```
✨ feat(auth): 대학 이메일 인증 코드 입력 화면 구현

- DESIGN.md 03 인증코드 시안 기준으로 VerifyCodeScreen 구성
- 6자리 입력 상태를 VerifyCodeUiState 로 통합
- VerifyCodeViewModelTest, VerifyCodeScreenTest 추가
```

규칙:

- **이모지는 유니코드로 직접 넣는다** (`✨`). `:sparkles:` 코드는 GitHub 웹에서만 렌더링되고 `git log` 에서는 그대로 보인다
- **한 커밋에 이모지는 하나.** 두 개가 필요하면 커밋을 나눈다 (기능 `✨` → 테스트 `✅` → 문서 `📝`)
- **타입은 영문 소문자, 설명은 한국어**
- scope 는 기능 패키지명: `auth`, `profile`, `matching`, `chat`, `safety`, `billing`, `core`, `design`, `docs`
  - 백엔드 작업은 `backend`, 저장소 구조·설정 작업은 scope 를 생략한다

---

## 2. 타입 ↔ gitmoji 매핑 (기본 8종)

| 이모지 | 코드 | 타입 | 용도 |
| --- | --- | --- | --- |
| ✨ | `:sparkles:` | `feat` | 새 기능 |
| 🐛 | `:bug:` | `fix` | 버그 수정 |
| 💄 | `:lipstick:` | `ui` | 화면/스타일 변경 (기능 변화 없음) |
| ♻️ | `:recycle:` | `refactor` | 동작 변화 없는 구조 개선 |
| ✅ | `:white_check_mark:` | `test` | 테스트 추가·수정 |
| 🔧 | `:wrench:` | `chore` | 빌드·의존성·설정 |
| 📝 | `:memo:` | `docs` | 문서 |
| 🎨 | `:art:` | `design` | 디자인 시스템·시안 |

> 🎨 는 표준 gitmoji 에서 "코드 구조/포맷 개선" 이지만 **이 프로젝트에서는 `design` 에 배정한다.**
> 코드 구조 개선은 `♻️ refactor` 가 담당한다. 이 표가 [gitmoji.dev](https://gitmoji.dev) 표준보다 우선한다.

---

## 3. 보조 gitmoji

기본 8종으로 부족할 때만 쓴다. 타입은 그대로 붙인다 (예: `🗃️ chore(core): ...`).

| 이모지 | 코드 | 용도 | 이 프로젝트에서 |
| --- | --- | --- | --- |
| 🗃️ | `:card_file_box:` | DB 관련 변경 | Supabase 마이그레이션·스키마 |
| 🔒 | `:lock:` | 보안 수정 | RLS 정책, 키 취급 |
| ➕ | `:heavy_plus_sign:` | 의존성 추가 | **추가 전 사용자 확인 필수** |
| ➖ | `:heavy_minus_sign:` | 의존성 제거 | |
| 🔥 | `:fire:` | 코드·파일 삭제 | |
| 🚚 | `:truck:` | 파일·리소스 이동·이름 변경 | 패키지·저장소 구조 정리 |
| 🙈 | `:see_no_evil:` | `.gitignore` 수정 | |
| 💡 | `:bulb:` | 주석 추가·수정 | |
| ⚡️ | `:zap:` | 성능 개선 | |
| 🚑 | `:ambulance:` | 긴급 수정 | |
| 💚 | `:green_heart:` | CI 빌드 수정 | iOS 클라우드 빌드 |
| 👷 | `:construction_worker:` | CI 설정 추가·수정 | |
| 🔖 | `:bookmark:` | 릴리스 버전 태그 | |
| ⏪ | `:rewind:` | 변경 되돌리기 | |
| 🎉 | `:tada:` | 프로젝트 시작 | 저장소 최초 커밋 |

---

## 4. 브랜치 전략

**지금은 `main` + `feature/*` 두 가지만 쓴다.**

| 브랜치 | 역할 |
| --- | --- |
| `main` | 통합 브랜치. **직접 커밋·직접 푸시 금지** |
| `feature/*` | 모든 작업 단위. `main` 에서 분기해 **PR 로 `main` 에 병합** |

- 브랜치명은 **kebab-case**. 한글·공백·언더스코어 금지 (예: `feature/foundation-setup`)
- 작업 브랜치는 **로컬 `main` 에서 분기**한다. 로컬 `main` 이 원격보다 뒤처져 있으면 **당기지 말고 사용자에게 먼저 알린다** (§5.5)
- **merge 된 브랜치는 바로 지운다.** 브랜치 목록에 끝난 작업을 남기지 않는다 (§5.5)
- **`develop` · `release/*` · `hotfix/*` 는 첫 배포 이후에 도입한다.** 그 전까지 git flow 전체를 적용하지 않는다

---

## 5. 커밋·푸시·PR (Claude 대상)

### 5.1 역할 분담

| 단계 | 담당 |
| --- | --- |
| 커밋 | **Claude** |
| 푸시 (`feature/*`) | **Claude** |
| draft PR 생성 | **Claude** |
| 리뷰 후 최종 merge | **사용자** |
| merge 후 브랜치 삭제 | **Claude** (사용자가 merge 했다고 알려주면 자동) |
| `main` 당겨오기(pull) | **사용자가 요청할 때만** |

Claude 는 작업이 끝나면 **커밋 → 푸시 → draft PR 생성까지 진행하고 멈춘다.** merge 는 하지 않는다.
모든 작업은 `git` / `gh` **명령어로만** 수행한다.

### 5.2 커밋 규칙

- `git add -A` 대신 **변경한 파일을 이름으로 지정**해 스테이징한다 (비밀값 혼입 방지)
- 스테이징 후 `git status` 로 의도한 파일만 올라갔는지 확인한다
- **테스트가 없는 비-private 클래스가 포함된 상태로는 커밋하지 않는다**
- **커밋 메시지에 도구 표식을 붙이지 않는다.** `Co-Authored-By: Claude ...`, `Claude-Session: ...`,
  `🤖 Generated with ...` 같은 줄은 커밋 메시지에도 PR 본문에도 넣지 않는다 (2026-09-12 사용자 결정)

### 5.3 푸시 전 확인

1. `git status` — 키·`.env`·인증서·실존 인물 사진이 섞이지 않았는지
2. `flutter analyze` / `flutter test` 통과 (`frontend/` 변경 시)
3. 현재 브랜치가 `feature/*` 인지 — **`main` 직접 푸시 금지**

금지 사항:

- **`git push --force` 금지.** 필요해 보여도 실행하지 말고 사용자에게 먼저 묻는다
- `--no-verify` 등 훅 우회 금지
- 키가 포함된 커밋은 푸시하지 않는다. 이미 커밋했다면 푸시 전에 사용자에게 알린다

### 5.4 PR 규칙

```bash
gh pr create --draft --base main --title "<이모지> <타입>: <요약>" --body "..."
```

- **항상 `--draft`** 로 만든다. 리뷰·merge 는 사용자가 한다
- 제목은 커밋과 같은 형식 (`<이모지> <타입>: <요약>`)
- 본문에는 **변경 요약** 과 **사용자가 확인해야 할 지점** 을 적는다
- base 브랜치는 `main`

### 5.5 merge 이후 정리 (2026-09-12 사용자 결정)

**브랜치 삭제는 Claude 가 자동으로 한다.**
사용자가 "PR 했어" · "merge 했어" 라고 알리면, 따로 물지 않고 해당 `feature/*` 브랜치를 로컬과 원격 양쪽에서 지운다.

```bash
git branch -d <branch>                  # -D 는 쓰지 않는다 (merge 안 된 브랜치 보호)
git push origin --delete <branch>
git remote prune origin
```

- `git branch -d` 가 거부하면 **merge 되지 않은 작업이 남아 있다는 뜻**이다. `-D` 로 강제하지 말고 사용자에게 알린다
- `git branch -r --merged origin/main` 으로 예전에 남은 merge 된 원격 브랜치도 같이 정리한다
- `main` 과 `origin/HEAD` 는 당연히 지우지 않는다

**pull 은 Claude 가 먼저 하지 않는다.**
merge 는 GitHub 서버에서 일어나므로 로컬 `main` 은 그대로 뒤처져 있다. 그래도 **`git pull` · `git merge origin/main` 은 사용자가 요청할 때만 실행한다.**

- 상태 확인용 `git fetch` 와 `git status` 는 작업 트리를 바꾸지 않으므로 자유롭게 쓴다
- 로컬 `main` 이 뒤처져 있으면 **몇 커밋 차이인지 알리고 기다린다.** 새 작업을 시작해야 하는 상황이면 그 사실을 명시한다

---

## 6. gitmoji-cli (선택)

이모지를 직접 타이핑하는 대신 CLI 로 고를 수 있다. Node.js 가 필요하다.

```bash
npm i -g gitmoji-cli
gitmoji -c        # git add 이후 실행
```

> CLI 는 표준 gitmoji 목록을 보여주므로 **2·3절 표와 다른 이모지도 뜬다.** 이 문서의 표를 기준으로 고른다.
> Claude 는 CLI(대화형)를 쓰지 않고 `git commit -m` 에 이모지를 직접 넣는다.

참고: [Gitmoji 사용법 (inpa.tistory.com)](https://inpa.tistory.com/entry/GIT-%E2%9A%A1%EF%B8%8F-Gitmoji-%EC%82%AC%EC%9A%A9%EB%B2%95-Gitmoji-cli) · [gitmoji.dev](https://gitmoji.dev)
