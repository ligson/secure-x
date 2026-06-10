#!/usr/bin/env python3
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


API_BASE_URL = os.environ.get("PGYER_API_BASE_URL", "https://api.pgyer.com/apiv2").rstrip("/")


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def field(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def multipart_body(fields: dict[str, str], file_field: tuple[str, str] | None = None) -> tuple[bytes, str]:
    boundary = "----securex-pgyer-boundary"
    body = bytearray()
    for key, value in fields.items():
        body.extend(f"--{boundary}\r\n".encode())
        body.extend(f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode())
        body.extend(value.encode())
        body.extend(b"\r\n")

    if file_field is not None:
        name, path = file_field
        filename = os.path.basename(path)
        body.extend(f"--{boundary}\r\n".encode())
        body.extend(
            (
                f'Content-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'
                "Content-Type: application/octet-stream\r\n\r\n"
            ).encode()
        )
        with open(path, "rb") as app_file:
            body.extend(app_file.read())
        body.extend(b"\r\n")

    body.extend(f"--{boundary}--\r\n".encode())
    return bytes(body), boundary


def post_multipart(url: str, fields: dict[str, str], file_field: tuple[str, str] | None = None) -> tuple[int, str]:
    body, boundary = multipart_body(fields, file_field)
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=1800) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode(errors="replace")
    except Exception as exc:
        fail(f"PGYER request failed: {exc}")


def get_json(url: str) -> dict:
    try:
        with urllib.request.urlopen(url, timeout=120) as response:
            return json.loads(response.read().decode())
    except Exception as exc:
        fail(f"PGYER request failed: {exc}")


def parse_json(payload: str) -> dict:
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        fail(f"PGYER returned non-JSON response: {payload}")


def get_upload_token(api_key: str, app_path: str) -> dict:
    build_type = os.path.splitext(app_path)[1].lstrip(".").lower()
    install_type = field("PGYER_BUILD_INSTALL_TYPE")
    build_password = field("PGYER_BUILD_PASSWORD")
    if install_type == "2" and not build_password:
        print(
            "PGYER_BUILD_INSTALL_TYPE is 2 but PGYER_BUILD_PASSWORD is empty; "
            "falling back to public installation.",
            file=sys.stderr,
        )
        install_type = "1"

    fields = {
        "_api_key": api_key,
        "buildType": build_type,
        "buildInstallType": install_type,
        "buildPassword": build_password,
        "buildUpdateDescription": field("PGYER_BUILD_UPDATE_DESCRIPTION"),
        "buildInstallDate": field("PGYER_BUILD_INSTALL_DATE"),
        "buildInstallStartDate": field("PGYER_BUILD_INSTALL_START_DATE"),
        "buildInstallEndDate": field("PGYER_BUILD_INSTALL_END_DATE"),
        "buildChannelShortcut": field("PGYER_BUILD_CHANNEL_SHORTCUT"),
    }
    fields = {key: value for key, value in fields.items() if value}

    status, payload = post_multipart(f"{API_BASE_URL}/app/getCOSToken", fields)
    if status >= 400:
        fail(f"PGYER getCOSToken HTTP error {status}: {payload}")
    result = parse_json(payload)
    if result.get("code") != 0:
        fail(f"PGYER getCOSToken rejected: {json.dumps(result, ensure_ascii=False)}")
    return result.get("data") or {}


def upload_file(token: dict, app_path: str) -> str:
    params = token.get("params") or {}
    if isinstance(params, dict):
        token = {**params, **token}

    required = ["endpoint", "key", "signature", "x-cos-security-token"]
    missing = [name for name in required if not token.get(name)]
    if missing:
        fail(f"PGYER upload token missing fields: {', '.join(missing)}")

    fields = {
        "key": token["key"],
        "signature": token["signature"],
        "x-cos-security-token": token["x-cos-security-token"],
        "x-cos-meta-file-name": os.path.basename(app_path),
    }
    status, payload = post_multipart(token["endpoint"], fields, ("file", app_path))
    if status != 204:
        fail(f"PGYER COS upload failed with HTTP {status}: {payload}")
    return token["key"]


def wait_for_build(api_key: str, build_key: str) -> dict:
    query = urllib.parse.urlencode({"_api_key": api_key, "buildKey": build_key})
    url = f"{API_BASE_URL}/app/buildInfo?{query}"
    last_payload: dict = {}
    for _ in range(60):
        payload = get_json(url)
        last_payload = payload
        if payload.get("code") == 0:
            return payload.get("data") or {}
        time.sleep(1)
    fail(f"PGYER build processing timed out: {json.dumps(last_payload, ensure_ascii=False)}")


def main() -> None:
    if len(sys.argv) != 2:
        fail("Usage: scripts/upload-pgyer.py <apk-or-ipa-path>")

    app_path = sys.argv[1]
    if not os.path.isfile(app_path):
        fail(f"App file not found: {app_path}")

    api_key = field("PGYER_API_KEY")
    if not api_key:
        fail("PGYER_API_KEY is required.")

    token = get_upload_token(api_key, app_path)
    build_key = upload_file(token, app_path)
    data = wait_for_build(api_key, build_key)
    app_name = data.get("buildName") or os.path.basename(app_path)
    version = data.get("buildVersion") or ""
    shortcut = data.get("buildShortcutUrl") or ""
    print(f"Uploaded {app_name} {version} to PGYER.")
    if shortcut:
        print(f"PGYER URL: https://www.pgyer.com/{shortcut}")


if __name__ == "__main__":
    main()
