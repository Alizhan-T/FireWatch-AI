"""Отправка пушей через Firebase Cloud Messaging (опционально)."""
from __future__ import annotations

import logging
from pathlib import Path

log = logging.getLogger("firewatch.push")

_app = None
_status = "not_configured"


def init_firebase(credentials_path: str | None) -> bool:
    global _app, _status
    if _app is not None:
        return True
    if not credentials_path or not Path(credentials_path).exists():
        _status = "not_configured"
        log.warning("FIREBASE_CREDENTIALS не задан/не найден — FCM выключен, "
                    "работают только in-app уведомления")
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials

        try:
            _app = firebase_admin.get_app()
        except ValueError:
            _app = firebase_admin.initialize_app(credentials.Certificate(credentials_path))
        _status = "enabled"
        log.info("Firebase initialized")
        return True
    except Exception as e:  # noqa: BLE001
        _status = f"error: {e}"
        log.error("Firebase init failed: %s", e)
        return False


def is_enabled() -> bool:
    return _app is not None


def status() -> str:
    return _status


def send_incident_alert(tokens: list[str], title: str, body: str, data: dict) -> dict:
    """Отправить уведомление на все токены. data — только строки (требование FCM)."""
    data = {k: str(v) for k, v in data.items() if v is not None}
    if not is_enabled():
        return {"enabled": False, "sent": 0, "failed": 0,
                "note": "FCM не настроен — уведомление доступно только внутри приложения"}
    if not tokens:
        return {"enabled": True, "sent": 0, "failed": 0, "note": "нет зарегистрированных устройств"}

    from firebase_admin import messaging

    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=title, body=body),
        data=data,
        apns=messaging.APNSConfig(
            headers={"apns-priority": "10", "apns-push-type": "alert"},
            payload=messaging.APNSPayload(aps=messaging.Aps(sound="default")),
        ),
    )
    try:
        resp = messaging.send_each_for_multicast(message)
    except Exception as e:  # noqa: BLE001
        log.error("FCM send failed: %s", e)
        return {"enabled": True, "sent": 0, "failed": len(tokens), "errors": [str(e)]}
    invalid = [
        tokens[i]
        for i, r in enumerate(resp.responses)
        if not r.success and r.exception is not None
        and type(r.exception).__name__ in ("UnregisteredError", "SenderIdMismatchError")
    ]
    return {
        "enabled": True,
        "sent": resp.success_count,
        "failed": resp.failure_count,
        "errors": [str(r.exception) for r in resp.responses if not r.success],
        "invalid_tokens": invalid,
    }
