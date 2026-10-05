"""notify_ntfy: no-op without a topic, correct POST payload with one."""

import httpx

from servers.shared import ntfy_service
from servers.shared.ntfy_service import notify_ntfy


def test_noop_without_topic(monkeypatch):
    calls: list = []
    monkeypatch.setattr(
        ntfy_service.httpx, "post", lambda *a, **k: calls.append((a, k))
    )
    monkeypatch.setattr(ntfy_service.settings, "ntfy_topic", "")
    notify_ntfy("title", "body")
    assert calls == []


def test_posts_payload_when_topic_set(monkeypatch):
    captured: dict = {}

    def fake_post(url, json=None, headers=None, timeout=None):
        captured.update(url=url, json=json, headers=headers)
        return httpx.Response(200, request=httpx.Request("POST", url))

    monkeypatch.setattr(ntfy_service.httpx, "post", fake_post)
    monkeypatch.setattr(ntfy_service.settings, "ntfy_topic", "firsaas-vicoa-test")
    monkeypatch.setattr(ntfy_service.settings, "ntfy_token", "tkn")
    monkeypatch.setattr(ntfy_service.settings, "ntfy_click_url", "https://dash")
    monkeypatch.setattr(ntfy_service.settings, "ntfy_server_url", "https://ntfy.sh")

    notify_ntfy("title", "body", ["incoming"])

    assert captured["url"] == "https://ntfy.sh/"
    assert captured["json"] == {
        "topic": "firsaas-vicoa-test",
        "title": "title",
        "message": "body",
        "tags": ["incoming"],
        "click": "https://dash",
    }
    assert captured["headers"] == {"Authorization": "Bearer tkn"}
