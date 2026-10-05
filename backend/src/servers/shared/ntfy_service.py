"""Fire-and-forget ntfy push for self-hosted deploys (phone buzz without FCM).

Self-host has no FCM/APNs credentials, so phone push is dead there. ntfy
(https://ntfy.sh — free, first-party iOS/Android apps) fills the gap with a
plain HTTP POST per event. Disabled unless NTFY_TOPIC is set; a delivery
failure only loses one buzz, never raises — same contract as the backend
broadcast bridge (backend/broadcast_bridge.py).
"""

import logging

import httpx

from shared.config import settings

logger = logging.getLogger(__name__)

_NTFY_TIMEOUT_SECONDS = 2.0


def notify_ntfy(title: str, body: str, tags: list[str] | None = None) -> None:
    """POST one notification to the configured ntfy topic. No-op when unset."""
    if not settings.ntfy_topic:
        return
    payload: dict = {
        "topic": settings.ntfy_topic,
        "title": title,
        "message": body,
        "tags": tags or [],
    }
    if settings.ntfy_click_url:
        payload["click"] = settings.ntfy_click_url
    headers = (
        {"Authorization": f"Bearer {settings.ntfy_token}"}
        if settings.ntfy_token
        else {}
    )
    try:
        response = httpx.post(
            f"{settings.ntfy_server_url.rstrip('/')}/",
            json=payload,
            headers=headers,
            timeout=_NTFY_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
    except httpx.HTTPError as exc:
        # `ntfy_failure` is the stable marker to grep for when buzzes stop.
        logger.warning("ntfy_failure err=%s", exc)
