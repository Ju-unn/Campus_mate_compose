from uuid import UUID

import httpx

from app.graduate_verification.storage import BUCKET, GraduateCertStorage

PROFILE = UUID("11111111-1111-1111-1111-111111111111")
REQUEST = UUID("22222222-2222-2222-2222-222222222222")
URL = "https://x.supabase.co/storage/v1"


def _storage(handler) -> GraduateCertStorage:
    return GraduateCertStorage(URL, "service-key", httpx.AsyncClient(transport=httpx.MockTransport(handler)))


async def test_storage_upload_path_and_extension():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"Key": "ok"})

    storage = _storage(handler)

    jpg = await storage.upload(PROFILE, REQUEST, b"jpeg-bytes", "image/jpeg")
    png = await storage.upload(PROFILE, REQUEST, b"png-bytes", "image/png")

    assert BUCKET == "graduate-cert-temp"
    assert jpg == f"{PROFILE}/{REQUEST}.jpg"
    assert png == f"{PROFILE}/{REQUEST}.png"
    assert str(seen[0].url) == f"{URL}/object/graduate-cert-temp/{jpg}"
    assert seen[0].headers["content-type"] == "image/jpeg"
    assert seen[1].headers["content-type"] == "image/png"
    assert seen[0].headers["authorization"] == "Bearer service-key"
    assert seen[0].content == b"jpeg-bytes"


async def test_storage_delete_treats_404_as_deleted_and_swallows_network_errors():
    assert await _storage(lambda r: httpx.Response(200, json=[])).delete("p/r.jpg") is True
    assert await _storage(lambda r: httpx.Response(404, json={"error": "not_found"})).delete("p/r.jpg") is True
    assert await _storage(lambda r: httpx.Response(500)).delete("p/r.jpg") is False

    def boom(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("down")

    assert await _storage(boom).delete("p/r.jpg") is False


async def test_storage_signed_url_is_absolute():
    seen: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return httpx.Response(200, json={"signedURL": "/object/sign/graduate-cert-temp/p/r.jpg?token=t"})

    url = await _storage(handler).create_signed_url("p/r.jpg", 300)

    assert url == f"{URL}/object/sign/graduate-cert-temp/p/r.jpg?token=t"
    assert str(seen[0].url) == f"{URL}/object/sign/graduate-cert-temp/p/r.jpg"
    assert b'"expiresIn"' in seen[0].content and b"300" in seen[0].content
