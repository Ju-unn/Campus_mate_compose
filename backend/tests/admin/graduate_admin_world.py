"""관리자 졸업생 인증 검수 시험용 Supabase 가짜. 관문(로그인 · 2단계 · 명단)과 결과 알림 쪽(프로필 상태 · 알림 설정 · 기기 · FCM)은
AdminWorld 를 이어받아 쓰고, 졸업생 신청 표 · 학교 · 도메인 · 재가입 제한 · 비공개 버킷 · DB 함수만 여기서 흉내 낸다.

요청은 경로 + params **키**로 가른다(메모 reference_backend_test_mock_traps ①)."""
import json
from datetime import datetime

import httpx

from admin_world import AdminWorld
from app.core.time import SEOUL

BUCKET_PATH = "/storage/v1/object/graduate-cert-temp/"
SIGN_PATH = "/storage/v1/object/sign/graduate-cert-temp/"
TABLE = "/rest/v1/graduate_verification_requests"
RPC = "/rest/v1/rpc/admin_review_graduate_request"
APPLICANT = "cccccccc-0000-0000-0000-00000000000a"
OTHER_PERSON = "cccccccc-0000-0000-0000-00000000000b"
R1 = "99999999-0000-0000-0000-000000000001"
R2 = "99999999-0000-0000-0000-000000000002"
R3 = "99999999-0000-0000-0000-000000000003"
SNU = "aaaa0000-0000-0000-0000-000000000001"
KAIST = "aaaa0000-0000-0000-0000-000000000002"
HMAC_HEX = "feedfacecafebeef"


def request_row(rid: str = R1, profile_id: str = APPLICANT, *, status: str = "pending", reason: str | None = None,
                created_at: str = "2026-10-25T01:00:00+00:00", decided_at: str | None = None, photo: str | None = "default",
                ocr_state: str = "read", number: str | None = "AB12CD34", school: str | None = "서울대학교",
                previous: str | None = "old@snu.ac.kr", document_hmac: str | None = f"\\x{HMAC_HEX}") -> dict:
    """graduate_verification_requests 한 줄 — DB 칸 그대로. 결정된 줄은 평문 칸이 비어 있다."""
    decided = status != "pending"
    return {
        "id": rid, "profile_id": profile_id, "status": status, "reason": reason, "created_at": created_at,
        "decided_at": decided_at or ("2026-10-26T00:00:00+00:00" if decided else None),
        "photo_path": f"{profile_id}/{rid}.jpg" if photo == "default" else photo,
        "ocr_state": ocr_state, "ocr_document_number": None if decided else number,
        "ocr_school_text": None if decided else school, "previous_school_email": None if decided else previous,
        "document_hmac": document_hmac,
    }


class GraduateAdminWorld(AdminWorld):

    def __init__(self) -> None:
        super().__init__()
        self.now = datetime(2026, 10, 25, 12, 0, tzinfo=SEOUL)
        self.rows: dict[str, dict] = {}
        self.universities = [{"id": SNU, "name": "서울대학교"}, {"id": KAIST, "name": "카이스트"}]
        self.domains = {"snu.ac.kr": SNU, "kaist.ac.kr": KAIST}
        # 학교 메일 claims(AdminWorld.claims 와 같은 표) 주인의 프로필 상태, 재가입 제한 해시들
        self.claim_owner_status = "active"
        self.blocks: list[str] = []
        self.objects: dict[str, bytes] = {}
        self.unsignable: set[str] = set()
        self.fail_delete = False
        self.rpc_calls: list[dict] = []
        self.rpc_error: tuple[str, str] | None = None  # (Postgres 코드, 메시지)
        self.events: list[str] = []
        # 신청자 프로필 줄(profile:profiles(status,nickname,universities(name),…) 임베드가 돌려주는 칸). 사람 id → 칸.
        self.people: dict[str, dict] = {APPLICANT: {"status": "active", "nickname": "하늘", "universities": {"name": "서울대학교"}}}

    # --- 요청 보기 ---------------------------------------------------------------------------------
    def add(self, row: dict) -> dict:
        self.rows[row["id"]] = row
        if row["photo_path"]:
            self.objects[row["photo_path"]] = b"jpeg"
        return row

    def touched(self, path: str, method: str | None = None) -> list[httpx.Request]:
        return [r for r in self.requests if r.url.path == path and (method is None or r.method == method)]

    # --- 가짜 ---------------------------------------------------------------------------------------
    def handle(self, request: httpx.Request) -> httpx.Response:
        path, params, method = request.url.path, request.url.params, request.method
        if path == TABLE:
            self.requests.append(request)
            return self._table(request)
        if path == RPC:
            self.requests.append(request)
            return self._rpc(request)
        if path.startswith(SIGN_PATH) and method == "POST":
            self.requests.append(request)
            object_path = path.removeprefix(SIGN_PATH)
            if object_path in self.unsignable:
                return httpx.Response(400, json={"error": "not_found"})
            return httpx.Response(200, json={"signedURL": f"/object/sign/graduate-cert-temp/{object_path}?token=t"})
        if path.startswith(BUCKET_PATH) and method == "DELETE":
            self.requests.append(request)
            self.events.append("delete_photo")
            if self.fail_delete:
                return httpx.Response(500, json={"message": "boom"})
            self.objects.pop(path.removeprefix(BUCKET_PATH), None)
            return httpx.Response(200, json=[])
        if path == "/rest/v1/universities" and method == "GET":
            self.requests.append(request)
            return httpx.Response(200, json=self.universities)
        if path == "/rest/v1/university_email_domains" and method == "GET":
            self.requests.append(request)
            found = self.domains.get(params["domain"].removeprefix("eq."))
            return httpx.Response(200, json=[{"university_id": found}] if found else [])
        if path == "/rest/v1/signup_blocks" and method == "GET":
            self.requests.append(request)
            hit = params["email_hmac"].removeprefix("eq.") in self.blocks
            return httpx.Response(200, json=[{"blocked_until": "2099-01-01T00:00:00+00:00"}] if hit else [])
        if path == "/rest/v1/school_email_claims" and method == "GET" and "school_email_hmac" in params:
            self.requests.append(request)
            rows = [c for c in self.claims if c["school_email_hmac"] == params["school_email_hmac"].removeprefix("eq.")]
            return httpx.Response(200, json=[{"profile_id": c["profile_id"], "profiles": {"status": self.claim_owner_status}}
                                             for c in rows])
        if path == "/rest/v1/profiles" and method == "GET" and params.get("select") == "status":
            # push.notify() 의 정지 · 탈퇴 관문. 신청자의 지금 상태를 돌려준다.
            self.requests.append(request)
            return httpx.Response(200, json=[{"status": self.profile_status}])
        if path == "/rest/v1/notifications" and method == "POST":
            self.events.append("notice")
        if path.startswith("/v1/projects/") and path.endswith("/messages:send"):
            self.events.append("push")
        return super().handle(request)

    def _table(self, request: httpx.Request) -> httpx.Response:
        params, method = request.url.params, request.method
        if method == "PATCH":  # 사진 경로 비우기
            self.events.append("clear_path")
            assert params["status"] == "neq.pending"
            row = self.rows.get(params["id"].removeprefix("eq."))
            if row and row["status"] != "pending":
                row.update(json.loads(request.content))
            return httpx.Response(204)
        assert method == "GET"
        if "document_hmac" in params:  # 같은 번호로 승인된 다른 사람
            assert params["status"] == "eq.approved"
            hit = [r for r in self.rows.values() if r["status"] == "approved"
                   and r["document_hmac"] == params["document_hmac"].removeprefix("eq.")
                   and r["profile_id"] != params["profile_id"].removeprefix("neq.")]
            return httpx.Response(200, json=[{"profile_id": r["profile_id"]} for r in hit[:1]])
        if "profile_id" in params:  # 지난 신청들(이 줄 빼고)
            rows = [r for r in self.rows.values() if r["profile_id"] == params["profile_id"].removeprefix("eq.")
                    and r["id"] != params["id"].removeprefix("neq.")]
            rows.sort(key=lambda r: r["created_at"], reverse=True)
            return httpx.Response(200, json=[
                {"status": r["status"], "reason": r["reason"], "decided_at": r["decided_at"]} for r in rows[:int(params["limit"])]])
        if "id" in params:
            row = self.rows.get(params["id"].removeprefix("eq."))
            return httpx.Response(200, json=[self._embed(row, params["select"])] if row else [])
        status = params["status"].removeprefix("eq.")
        rows = sorted((r for r in self.rows.values() if r["status"] == status), key=lambda r: r["created_at"])
        return httpx.Response(200, json=[self._embed(r, params["select"]) for r in rows[:int(params["limit"])]])

    def _embed(self, row: dict, select: str) -> dict:
        """PostgREST 처럼 select 에 적은 칸만 돌려주고, profile:profiles(all_requests:…) 임베드는 같은 사람의 신청들로 채운다."""
        mine = [{"id": r["id"], "created_at": r["created_at"]} for r in self.rows.values() if r["profile_id"] == row["profile_id"]]
        names, depth, current = [], 0, ""
        for ch in select:
            depth += ch == "("
            depth -= ch == ")"
            if ch == "," and depth == 0:
                names.append(current)
                current = ""
            else:
                current += ch
        names.append(current)
        picked = {name: row[name] for name in names if name in row}
        return {**picked, "profile": {**self.people.get(row["profile_id"], {}), "all_requests": mine}}

    def _rpc(self, request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        self.rpc_calls.append(body)
        self.events.append("rpc")
        if self.rpc_error:
            return httpx.Response(400, json={"code": self.rpc_error[0], "message": self.rpc_error[1]})
        row = self.rows[body["p_request"]]
        row.update(status=body["p_status"], reason=body["p_reason"], decided_at="2026-10-25T12:00:00+00:00",
                   ocr_document_number=None, ocr_school_text=None, previous_school_email=None)
        if body["p_status"] == "approved":
            row["document_hmac"] = body["p_document_hmac"]
        return httpx.Response(200, json={
            "id": row["id"], "profile_id": row["profile_id"], "status": row["status"], "reason": row["reason"],
            "university_id": body["p_university"], "decided_at": row["decided_at"]})

