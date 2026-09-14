# SETUP.md — 새 PC 에서 CampusMate 이어받기

**저장소에 들어오지 않는 것들이 있다. 새 환경에서 아래를 갖춘다.**

`frontend/CLAUDE.md` §12 에서 떼어낸 문서다(2026-09-15). Claude Code 대화 기록도 저장소에 없으니, 새 세션은 `frontend/CLAUDE.md` §12 1항대로 문서부터 읽는다.

1. **스킬 재설치**
   ```
   claude plugin marketplace add leonxlnx/taste-skill
   claude plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill
   claude plugin marketplace add pbakaus/impeccable
   claude plugin install taste-skill --scope user
   claude plugin install ui-ux-pro-max --scope user
   claude plugin install impeccable --scope user
   ```
2. **Pencil 앱 설치** — `.pen` 편집용. OneDrive `datingApp` 저장소에서 시안 작업을 할 때만 필요하고, 이 저장소에서 코드만 작업할 때는 필요 없다
3. **Pretendard 폰트 설치** — 없으면 시안 렌더링이 대체 폰트로 틀어진다
4. Flutter SDK, Supabase CLI, GitHub CLI(`gh` — draft PR 생성용)
5. **graphify** — 설치 · 커밋 hook · 첫 빌드 명령은 `docs/GRAPHIFY.md` §6 에 있다. `graphify-out/` 은 저장소에 없으니 반드시 로컬에서 빌드한다
6. **IDE 는 저장소 루트가 아니라 `frontend/` 를 연다.** Flutter 프로젝트 루트가 `frontend/` 이기 때문이다
7. **실존 인물 목업 이미지는 저장소에 없다**(`frontend/CLAUDE.md` §11, `.gitignore` 제외). 필요하면 OneDrive `datingApp` 저장소에서 로컬로만 가져온다
