"""졸업생 인증 신청자 API 시험이 같이 쓰는 Supabase 가짜.

요청은 URL 부분 문자열이 아니라 **경로 + params 키**로 가른다(메모 reference_backend_test_mock_traps ①).
모르는 요청은 바로 실패시킨다 — 서버가 엉뚱한 표(특히 school_email_claims · signup_blocks)를 부르면 조용히 []를 받고
통과하지 않게."""
import json
from datetime import datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
from google.cloud import vision

from app.consents.policy import CONSENT_VERSION, REQUIRED_KINDS
from app.core.time import SEOUL
from app.settings import Settings

PROFILE = "11111111-1111-1111-1111-111111111111"
NOW = datetime(2026, 10, 25, 12, 0, tzinfo=SEOUL)
AUTH = {"Authorization": "Bearer valid-token"}
JPEG = b"\xff\xd8\xff" + b"fake-certificate-bytes"
PNG = b"\x89PNG\r\n\x1a\n" + b"fake-png"
BUCKET_PATH = "/storage/v1/object/graduate-cert-temp/"
TABLE = "/rest/v1/graduate_verification_requests"


def settings() -> Settings:
    return Settings(
        supabase_url="https://x.supabase.co", supabase_service_role_key="service-key",
        auth_hook_signing_secret="whsec_test", discord_webhook_url="https://discord.com/api/webhooks/test",
        google_cloud_project="campus-mate-test", openai_api_key="sk-test",
        phone_encryption_key="phone-key-test", identity_hmac_key="identity-key-test",
    )


def request_row(status: str = "pending", reason: str | None = None, *, rid: str = "r1",
                created_at: str = "2026-10-24T00:00:00+00:00", photo_path: str | None = None) -> dict:
    return {"id": rid, "profile_id": PROFILE, "status": status, "reason": reason, "created_at": created_at,
            "photo_path": photo_path}


class ApplicantWorld:
    """PROFILE 한 명(졸업생 길을 고를 수 있는 사람)이 사는 세상. 로그인한 사람은 늘 PROFILE 이다."""

    def __init__(self, *, method: str | None = "graduate_certificate", verified: bool = False, status: str = "active",
                 consented: bool = True, rows: list[dict] | None = None, ocr_text: str = "") -> None:
        self.requests: list[httpx.Request] = []
        self.profile = {
            "status": status, "student_verification": "verified", "department": None, "universities": {"name": "서울대학교"},
            "school_email_verified_at": "2026-10-01T00:00:00+00:00" if verified else None,
            "verification_method": method, "graduate_verified_at": None,
        }
        self.consented = consented
        self.rows: list[dict] = rows if rows is not None else []
        self.objects: dict[str, bytes] = {}
        self.discord: list[dict] = []
        self.universities = [{"id": "u-snu", "name": "서울대학교"}, {"id": "u-kaist", "name": "카이스트"}]
        # 실패 주입
        self.fail_upload = False
        self.fail_delete = False
        self.fail_insert = False
        self.insert_conflict = False
        self.vision = AsyncMock(spec=vision.ImageAnnotatorAsyncClient)
        self.set_ocr(ocr_text)

    def set_ocr(self, text: str) -> None:
        annotations = [SimpleNamespace(description=text)] if text else []
        self.vision.batch_annotate_images.return_value = SimpleNamespace(
            responses=[SimpleNamespace(error=SimpleNamespace(message=""), text_annotations=annotations)])

    # --- 요청 보기 ---------------------------------------------------------------------------------
    def calls(self, method: str, path_end: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.method == method and r.url.path.endswith(path_end)]

    def touched(self, path_end: str) -> list[httpx.Request]:
        return [r for r in self.requests if r.url.path.endswith(path_end)]

    # --- 가짜 ---------------------------------------------------------------------------------------
    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        path, params, method = request.url.path, request.url.params, request.method
        if path == "/auth/v1/user":
            return httpx.Response(200, json={"id": PROFILE})
        if path == "/rest/v1/profiles":
            if method == "GET":
                assert params["id"] == f"eq.{PROFILE}"
                return httpx.Response(200, json=[self.profile])
            self.profile.update(json.loads(request.content))
            return httpx.Response(204)
        if path == "/rest/v1/user_consents":
            rows = [{"kind": k, "version": CONSENT_VERSION} for k in sorted(REQUIRED_KINDS)] if self.consented else []
            return httpx.Response(200, json=rows)
        if path == "/rest/v1/universities":
            return httpx.Response(200, json=self.universities)
        if path == TABLE:
            return self._requests_table(request)
        if path.startswith(BUCKET_PATH):
            return self._storage(request, path.removeprefix(BUCKET_PATH))
        if request.url.host == "discord.com":
            self.discord.append(json.loads(request.content))
            return httpx.Response(204)
        raise AssertionError(f"신청자 가짜가 모르는 요청 {method} {path}")

    def _requests_table(self, request: httpx.Request) -> httpx.Response:
        params, method = request.url.params, request.method
        if method == "GET":
            rows = [r for r in self.rows if r["profile_id"] == params["profile_id"].removeprefix("eq.")]
            return httpx.Response(200, json=sorted(rows, key=lambda r: r["created_at"], reverse=True))
        if method == "POST":
            if self.insert_conflict:
                return httpx.Response(409, json={"code": "23505", "message": "duplicate key"})
            if self.fail_insert:
                return httpx.Response(500, json={"message": "boom"})
            body = json.loads(request.content)
            self.rows.append({**body, "status": "pending", "reason": None, "created_at": NOW.isoformat()})
            return httpx.Response(201)
        assert method == "PATCH"
        body = json.loads(request.content)
        if "profile_id" in params:  # 대기 신청 취소
            hit = [r for r in self.rows if r["profile_id"] == params["profile_id"].removeprefix("eq.")
                   and r["status"] == params["status"].removeprefix("eq.")]
            for row in hit:
                row.update(body)
            return httpx.Response(200, json=[{"id": r["id"], "photo_path": r.get("photo_path")} for r in hit])
        assert "id" in params and params["status"] == "neq.pending"  # 사진 경로 비우기
        for row in self.rows:
            if row["id"] == params["id"].removeprefix("eq.") and row["status"] != "pending":
                row.update(body)
        return httpx.Response(204)

    def _storage(self, request: httpx.Request, object_path: str) -> httpx.Response:
        if request.method == "POST":
            if self.fail_upload:
                return httpx.Response(500, json={"message": "boom"})
            self.objects[object_path] = request.content
            return httpx.Response(200, json={"Key": object_path})
        assert request.method == "DELETE"
        if self.fail_delete:
            return httpx.Response(500, json={"message": "boom"})
        self.objects.pop(object_path, None)
        return httpx.Response(200, json=[])
