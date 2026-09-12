# campus_mate_compose (workspace)

이 폴더는 개별 git 저장소가 아니라, 두 저장소를 함께 열어두는 workspace다.

- `campus_mate_frontend/` — Flutter 앱 (자체 git 저장소, github.com/Ju-unn/campus_mate)
- `campus_mate_backend/` — FastAPI 백엔드 자리 (조각 4에서 시작, 아직 코드 없음)
- `docs/` — 두 저장소가 공통으로 참조하는 설계 문서 (제품·아키텍처·매칭·보안 스펙, 조각 0 계획)

프론트엔드 전용 문서(`DESIGN.md`, `CLAUDE.md`, `AGENTS.md`)는 `campus_mate_frontend/` 안에 그대로 있다.
