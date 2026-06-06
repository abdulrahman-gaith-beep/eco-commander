"""
Gemini CLI quota source.

Replays the same Code Assist API call that gemini-cli's TUI uses to
render the model-picker quota panel:
  POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist

Auth: bearer token from ~/.gemini/oauth_creds.json (auto-refreshed via the
Google OAuth token endpoint when expired).

Endpoint and field names are from the published @google/gemini-cli npm
bundle. OAuth client credentials are operator-local and must be supplied via
ECO_GEMINI_OAUTH_CLIENT_ID / ECO_GEMINI_OAUTH_CLIENT_SECRET.

Server-truth polling is opt-in via config.json server_truth.gemini and the
OAuth client env vars. When it is disabled, collect() returns a zeroed local
estimate without reading OAuth credentials or calling Code Assist.

Response parsing is best-effort because the schema is unstable across CLI
versions. Raw API dumps are disabled by default; set ECO_GEMINI_DEBUG_DUMP=1
for local operator debugging.
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from . import discovery
from . import pace as _pace_mod
from .time_utils import format_resets_in as _format_resets_in
from .time_utils import parse_iso_to_epoch as _parse_iso_to_epoch

GEMINI_DIR = Path.home() / ".gemini"
OAUTH_PATH = GEMINI_DIR / "oauth_creds.json"
LOG_DIR = Path(os.environ.get("ECO_HOME", Path.home() / ".eco")) / "logs"
DEBUG_DUMP = LOG_DIR / "gemini-loadcodeassist.json"

LOAD_ASSIST_ENDPOINT = "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"
QUOTA_ENDPOINT = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
TOKEN_REFRESH_ENDPOINT = "https://oauth2.googleapis.com/token"

GEMINI_CLIENT_ID_ENV = "ECO_GEMINI_OAUTH_CLIENT_ID"
GEMINI_CLIENT_SECRET_ENV = "ECO_GEMINI_OAUTH_CLIENT_SECRET"

REQUEST_TIMEOUT = 8

ACCOUNTS_REGISTRY = GEMINI_DIR / "google_accounts.json"

PER_ACCOUNT_NOTE = (
    "gemini-cli stores only the active account's OAuth on disk; "
    "non-active accounts require `gemini` swap to populate live data."
)
UNKNOWN_PLAN = "Unknown"


def _server_truth_enabled() -> bool:
    return discovery.server_truth_enabled("gemini")


def _missing_oauth_client_env() -> list[str]:
    return [
        name for name in (GEMINI_CLIENT_ID_ENV, GEMINI_CLIENT_SECRET_ENV)
        if not os.environ.get(name)
    ]


def _oauth_client_credentials() -> tuple[str, str] | None:
    if _missing_oauth_client_env():
        return None
    return (
        os.environ[GEMINI_CLIENT_ID_ENV],
        os.environ[GEMINI_CLIENT_SECRET_ENV],
    )


def _zero_tiers() -> dict:
    return {
        "flash":      {"pct": 0.0, "resets_in": "—"},
        "flash_lite": {"pct": 0.0, "resets_in": "—"},
        "pro":        {"pct": 0.0, "resets_in": "—"},
    }


def _account_slugs(active_email: str | None, old_emails: list[str]) -> list[str]:
    # Never expose raw account emails as stable identifiers in output.
    count = 1 + len(old_emails)
    return ["primary"] + [f"account-{i}" for i in range(2, count + 1)]


def _jsonl_estimate_payload(reason: str) -> dict:
    active_email, old_emails = _enumerate_accounts()
    slugs = _account_slugs(active_email, old_emails)
    return {
        "tool": "gemini",
        "ok": True,
        "source": "jsonl-estimate",
        "note": reason,
        "tiers": _zero_tiers(),
        "accounts": len(slugs),
        "per_account": [
            {"slug": s, "plan": UNKNOWN_PLAN, "ok": True, "source": "jsonl-estimate"}
            for s in slugs
        ],
        "per_account_note": PER_ACCOUNT_NOTE,
    }


def _enumerate_accounts() -> tuple[str | None, list[str]]:
    """Return (active_email, [old_emails]) from google_accounts.json.

    Returns (None, []) if the registry is missing or malformed — caller
    falls back to a single 'primary' account.
    """
    if not ACCOUNTS_REGISTRY.exists():
        return None, []
    try:
        data = json.loads(ACCOUNTS_REGISTRY.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None, []
    if not isinstance(data, dict):
        return None, []
    active = data.get("active") if isinstance(data.get("active"), str) else None
    old_raw = data.get("old")
    old = old_raw if isinstance(old_raw, list) else []
    old = [e for e in old if isinstance(e, str) and e]
    return active, old


def _load_oauth() -> tuple[dict | None, str | None]:
    if not OAUTH_PATH.exists():
        return None, "oauth_creds.json missing — run `gemini` once to authenticate"
    try:
        d = json.loads(OAUTH_PATH.read_text())
    except (OSError, json.JSONDecodeError):
        return None, "oauth_creds.json unreadable"
    if not d.get("access_token"):
        return None, "no access_token in oauth_creds.json"
    return d, None


def _save_oauth(creds: dict) -> None:
    payload = json.dumps(creds)
    try:
        OAUTH_PATH.parent.mkdir(parents=True, exist_ok=True)
        os.chmod(OAUTH_PATH.parent, 0o700)
        tmp = OAUTH_PATH.parent / f".{OAUTH_PATH.name}.tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as fh:
            fh.write(payload)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, OAUTH_PATH)
        os.chmod(OAUTH_PATH, 0o600)
    except OSError:
        pass  # non-fatal; just means we'll refresh again next cycle


def _refresh_if_needed(creds: dict) -> tuple[dict, str | None]:
    expiry_ms = creds.get("expiry_date") or 0
    # Refresh 5 min before actual expiry to avoid mid-request 401s.
    if expiry_ms and (expiry_ms / 1000) > (time.time() + 300):
        return creds, None
    refresh = creds.get("refresh_token")
    if not refresh:
        return creds, "no refresh_token; re-run `gemini` to re-auth"
    client_credentials = _oauth_client_credentials()
    if client_credentials is None:
        missing = ", ".join(_missing_oauth_client_env())
        return creds, f"Gemini OAuth client env missing: {missing}"
    client_id, client_secret = client_credentials
    body = urllib.parse.urlencode({
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": refresh,
        "grant_type": "refresh_token",
    }).encode()
    req = urllib.request.Request(
        TOKEN_REFRESH_ENDPOINT,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
            payload = json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        return creds, f"token refresh HTTP {exc.code}"
    except urllib.error.URLError:
        return creds, "token refresh network error"
    except (json.JSONDecodeError, OSError):
        return creds, "token refresh parse error"

    new_token = payload.get("access_token")
    if not new_token:
        return creds, "refresh response missing access_token"
    creds = {
        **creds,
        "access_token": new_token,
        "expiry_date": int((time.time() + int(payload.get("expires_in", 3600))) * 1000),
    }
    _save_oauth(creds)
    return creds, None


def _post(url: str, token: str, body: dict, dump_path: Path | None = None) -> tuple[dict | None, str | None]:
    payload = json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        return None, f"HTTP {exc.code}"
    except urllib.error.URLError:
        return None, "network error"
    except (json.JSONDecodeError, OSError):
        return None, "parse error"

    if dump_path is not None and _debug_dump_enabled():
        _write_private_json(dump_path, data)
    return data, None


def _debug_dump_enabled() -> bool:
    return os.environ.get("ECO_GEMINI_DEBUG_DUMP") == "1"


def _write_private_json(path: Path, data: dict) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.parent.chmod(0o700)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
    except OSError:
        pass


def _get_project_id(token: str) -> tuple[str | None, dict | None, str | None]:
    """retrieveUserQuota wants `{"project": <projectId>}`. Get it from
    loadCodeAssist's `cloudaicompanionProject` field."""
    data, err = _post(LOAD_ASSIST_ENDPOINT, token, {
        "metadata": {
            "ideType": "IDE_UNSPECIFIED",
            "platform": "PLATFORM_UNSPECIFIED",
            "pluginType": "GEMINI",
        }
    }, dump_path=DEBUG_DUMP)
    if err:
        return None, None, err
    pid = (data or {}).get("cloudaicompanionProject")
    if not pid:
        # Free-tier users may not have a project; pass empty and let
        # the server respond appropriately.
        pid = ""
    return pid, data, None


def _walk(node: Any):
    """Yield every dict in a nested structure for shape-tolerant lookup."""
    if isinstance(node, dict):
        yield node
        for v in node.values():
            yield from _walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from _walk(v)

def _normalize_tier_name(name: str) -> str | None:
    n = (name or "").lower().replace("-", "_").replace(" ", "_")
    if "flash_lite" in n or "flash-lite" in n:
        return "flash_lite"
    if "flash" in n:
        return "flash"
    if "pro" in n:
        return "pro"
    return None

def _pace_for_tier(used_pct: float, reset_epoch: float | None, now: float,
                   default_cycle_secs: float = 24 * 3600) -> dict:
    """Same pace-to-target logic as claude.py / codex.py.

    For Gemini, the cycle length is whatever Google's `resetTime` encodes
    (typically 24h for Code Assist). We back-compute the cycle start from
    ``reset_epoch - default_cycle_secs`` and reuse the shared classifier.
    Returns a dict including ``target_pct`` so existing call sites keep working.
    Adds ``reset_epoch`` (T4 fix #3) for notify.py cycle-reset detection.
    """
    if reset_epoch is None or reset_epoch <= now:
        cycle_start, cycle_end = now, now + default_cycle_secs
    else:
        cycle_end = reset_epoch
        cycle_start = cycle_end - default_cycle_secs
    pace_block = _pace_mod.build_pace_fields(used_pct, cycle_start, cycle_end, now)
    # Preserve the legacy key names callers used.
    return {
        "target_pct":  pace_block["target_pct"],
        "delta_pp":    pace_block["pace_delta_pp"],
        "label":       pace_block["pace_label"],
        "glyph":       pace_block["pace_glyph"],
        "reset_epoch": pace_block["reset_epoch"],
    }


def _extract_tiers(payload: dict, now: float) -> dict:
    """
    retrieveUserQuota response shape (verified against gemini-cli source):
      {
        "buckets": [
          {"modelId":"<id>", "remainingFraction":0.13,
           "remainingAmount":"123", "resetTime":"2026-..."},
          ...
        ]
      }
    """
    tiers: dict[str, dict[str, Any]] = {
        "flash":      {"pct": 0.0, "resets_in": "—"},
        "flash_lite": {"pct": 0.0, "resets_in": "—"},
        "pro":        {"pct": 0.0, "resets_in": "—"},
    }

    for bucket in (payload or {}).get("buckets") or []:
        if not isinstance(bucket, dict):
            continue
        model_id = bucket.get("modelId") or ""
        slot = _normalize_tier_name(model_id)
        if not slot:
            continue
        rem_frac = bucket.get("remainingFraction")
        if rem_frac is None:
            continue
        try:
            rem_frac_f = float(rem_frac)
        except (TypeError, ValueError):
            continue
        # remainingFraction is 0.0..1.0; pct used = (1 - frac) * 100
        pct = round(100 * (1.0 - rem_frac_f), 1)

        rem_amount = bucket.get("remainingAmount")
        limit = None
        try:
            if rem_amount and rem_frac_f > 0:
                limit = round(int(rem_amount) / rem_frac_f)
        except (TypeError, ValueError):
            limit = None

        reset_at = bucket.get("resetTime")
        reset_epoch = _parse_iso_to_epoch(reset_at) if isinstance(reset_at, str) else None
        resets_in = _format_resets_in(reset_epoch - now) if reset_epoch else "—"

        # Keep the worst (highest) pct for the slot if multiple buckets map
        # to the same tier (preview vs stable Pro, etc.).
        if pct >= tiers[slot]["pct"]:
            pace = _pace_for_tier(pct, reset_epoch, now)
            entry = {
                "pct": min(pct, 999.9),
                "resets_in": resets_in,
                "model_id": model_id,
                "target_pct": pace["target_pct"],
                "pace_delta_pp": pace["delta_pp"],
                "pace_label": pace["label"],
                "pace_glyph": pace["glyph"],
                # T4 fix #3 — notify.py needs this to detect cycle resets.
                "reset_epoch": pace["reset_epoch"],
            }
            if limit:
                entry["limit"] = limit
                entry["remaining"] = int(rem_amount) if rem_amount else None
            tiers[slot] = entry

    return tiers


def collect() -> dict:
    if not _server_truth_enabled():
        return _jsonl_estimate_payload(
            "Gemini server-truth disabled; enable server_truth.gemini to use Code Assist quota polling"
        )
    missing_env = _missing_oauth_client_env()
    if missing_env:
        return _jsonl_estimate_payload(
            f"Gemini server-truth disabled; set {', '.join(missing_env)}"
        )

    creds, err = _load_oauth()
    if err:
        return _stub(err)
    assert creds is not None
    creds, err = _refresh_if_needed(creds)
    if err:
        return _stub(err)

    project_id, _load_resp, err = _get_project_id(creds["access_token"])
    if err:
        return _stub(f"loadCodeAssist failed: {err}")

    quota_resp, err = _post(
        QUOTA_ENDPOINT, creds["access_token"],
        {"project": project_id or ""},
        dump_path=LOG_DIR / "gemini-userquota.json",
    )
    if err:
        return _stub(f"retrieveUserQuota failed: {err}")

    now = time.time()
    tiers = _extract_tiers(quota_resp or {}, now)
    if not (quota_resp or {}).get("buckets"):
        return _stub(
            "retrieveUserQuota returned no buckets"
        )

    active_email, old_emails = _enumerate_accounts()
    slugs = _account_slugs(active_email, old_emails)
    per_account: list[dict[str, Any]] = []
    per_account.append({
        "slug": slugs[0],
        "plan": UNKNOWN_PLAN,
        "ok": True,
        "source": "api",
        "tiers": tiers,
    })
    for slug in slugs[1:]:
        per_account.append({
            "slug": slug,
            "plan": UNKNOWN_PLAN,
            "ok": False,
            "source": "auth-not-present",
            "note": "swap to this account via `gemini` to populate",
        })

    return {
        "tool": "gemini",
        "ok": True,
        "source": "api",
        "user_tier": None,
        "tiers": tiers,
        "accounts": len(per_account),
        "per_account": per_account,
        "per_account_note": PER_ACCOUNT_NOTE,
    }


def _stub(reason: str) -> dict:
    # Name-only legacy; new callers should use _error_payload. Returns
    # source="error" so downstream consumers never see the word "stub".
    return _error_payload(reason)


def _error_payload(reason: str) -> dict:
    active_email, old_emails = _enumerate_accounts()
    slugs = _account_slugs(active_email, old_emails)
    return {
        "tool": "gemini",
        "ok": False,
        "source": "error",
        "error": reason,
        "tiers": _zero_tiers(),
        "accounts": len(slugs),
        "per_account": [
            {"slug": s, "plan": UNKNOWN_PLAN, "ok": False, "source": "error"}
            for s in slugs
        ],
        "per_account_note": PER_ACCOUNT_NOTE,
    }


if __name__ == "__main__":
    print(json.dumps(collect(), indent=2))
