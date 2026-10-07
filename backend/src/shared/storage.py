"""Thin S3 wrapper for message image attachments.

Credentials come from settings (.env / Fly secrets); when the credential
fields are empty, boto3's default chain (IAM role, ~/.aws/credentials,
real env vars) applies. Kept import-light so the module can be
monkeypatched in tests without AWS configuration.
"""

from pathlib import Path
from typing import Any

import boto3

from shared.config.settings import settings

ATTACHMENTS_BUCKET = "vicoa"

_EXT_BY_MIME = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "image/gif": "gif",
}


def attachment_key(user_id: str, attachment_id: str, mime_type: str) -> str:
    # The extension is cosmetic — the key is addressed by id, and the served
    # Content-Type comes from the DB row. Unknown types fall back to .bin
    # rather than raising, matching vicoa.attachments.save_attachment.
    ext = _EXT_BY_MIME.get(mime_type, "bin")
    return f"attachments/{user_id}/{attachment_id}.{ext}"


def project_icon_key(project_id: str) -> str:
    # Keyed by project_id ALONE (not {user_id}/…): a project may later move to a
    # team, so the object path must not encode a single owner (plan §9). No
    # extension — the served Content-Type comes from the stored object's own
    # metadata (download_object), so one deterministic key survives png↔jpeg
    # re-encodes across uploads.
    return f"project-icons/{project_id}"


def agent_profile_avatar_key(agent_profile_id: str) -> str:
    # Third of the same family (project icons / user avatars / agent avatars):
    # keyed by id alone so a profile can move to a team without rekeying, and no
    # extension so one key survives png<->jpeg re-encodes.
    return f"agent-avatars/{agent_profile_id}"


def team_avatar_key(team_id: str) -> str:
    # Fourth of the family (project icons / user / agent avatars): keyed by id
    # alone, no extension — the served Content-Type comes from the object.
    return f"team-avatars/{team_id}"


def user_avatar_key(user_id: str) -> str:
    # Same shape as project_icon_key: keyed by id alone, no extension — the
    # served Content-Type comes from the stored object's own metadata
    # (download_object), so one deterministic key survives png<->jpeg re-encodes
    # across uploads and re-seeds.
    return f"avatars/{user_id}"


def _client():
    kwargs: dict[str, Any] = {}
    if settings.aws_access_key_id and settings.aws_secret_access_key:
        kwargs["aws_access_key_id"] = settings.aws_access_key_id
        kwargs["aws_secret_access_key"] = settings.aws_secret_access_key
    if settings.aws_region:
        kwargs["region_name"] = settings.aws_region
    return boto3.client("s3", **kwargs)


# --- Local-disk backend (offline self-host) ---------------------------------
# With STORAGE_DIR set and no AWS credentials configured, objects live on disk
# under STORAGE_DIR instead of S3 — same keys, plus a tiny `<key>.ct` sidecar
# holding the content type so download_object can return it the way S3
# metadata would.

def _use_local() -> bool:
    return bool(settings.storage_dir) and not (
        settings.aws_access_key_id and settings.aws_secret_access_key
    )


def _local_path(key: str) -> Path:
    if ".." in key or key.startswith("/"):
        raise ValueError(f"invalid storage key: {key}")
    return Path(settings.storage_dir, key)


def _local_put(key: str, data: bytes, content_type: str) -> None:
    path = _local_path(key)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    path.with_name(f"{path.name}.ct").write_text(content_type)


def _local_get(key: str) -> tuple[bytes, str]:
    path = _local_path(key)
    content_type = "application/octet-stream"
    ct_path = path.with_name(f"{path.name}.ct")
    if ct_path.exists():
        content_type = ct_path.read_text().strip() or content_type
    return path.read_bytes(), content_type


def _local_delete(key: str) -> None:
    path = _local_path(key)
    path.with_name(f"{path.name}.ct").unlink(missing_ok=True)
    path.unlink(missing_ok=True)


def upload_attachment(key: str, data: bytes, mime_type: str) -> None:
    if _use_local():
        _local_put(key, data, mime_type)
        return
    _client().put_object(
        Bucket=ATTACHMENTS_BUCKET,
        Key=key,
        Body=data,
        ContentType=mime_type,
    )


def download_attachment(key: str) -> bytes:
    return download_object(key)[0]


def download_object(key: str) -> tuple[bytes, str]:
    """Fetch bytes plus the stored Content-Type (for keys with no DB mime row)."""
    if _use_local():
        return _local_get(key)
    obj = _client().get_object(Bucket=ATTACHMENTS_BUCKET, Key=key)
    return obj["Body"].read(), obj.get("ContentType") or "application/octet-stream"


def delete_object(key: str) -> None:
    if _use_local():
        _local_delete(key)
        return
    _client().delete_object(Bucket=ATTACHMENTS_BUCKET, Key=key)
