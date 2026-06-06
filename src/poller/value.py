"""API-equivalent value of subscription usage.

Financial figures are intentionally not embedded in the repository. To compute
USD value or subscription multipliers, set ``ECO_VALUE_MODEL_JSON`` to a JSON
export generated from the canonical financial model.

Expected external model shape::

    {
      "pricing": {
        "claude-sonnet": {"input": 0, "output": 0, "cached": 0}
      },
      "codex_credit_rates": {},
      "subscription_cost_monthly": 0
    }

Without that model, this module still returns a stable schema and marks the
value section as unavailable instead of inventing prices.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

PRICING: dict[str, dict[str, float]] = {}
CODEX_CREDIT_RATES: dict[str, dict[str, float]] = {}
SUBSCRIPTION_COST_MONTHLY: float | None = None


def _load_financial_model() -> dict[str, Any]:
    raw_path = os.environ.get("ECO_VALUE_MODEL_JSON")
    if not raw_path:
        return {}
    path = Path(raw_path).expanduser()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _as_rate_table(raw: Any) -> dict[str, dict[str, float]]:
    if not isinstance(raw, dict):
        return {}
    table: dict[str, dict[str, float]] = {}
    for model, rates in raw.items():
        if not isinstance(rates, dict):
            continue
        try:
            table[str(model)] = {
                "input": float(rates.get("input", 0) or 0),
                "output": float(rates.get("output", 0) or 0),
                "cached": float(rates.get("cached", 0) or 0),
            }
        except (TypeError, ValueError):
            continue
    return table


def _optional_float(raw: Any) -> float | None:
    try:
        return float(raw)
    except (TypeError, ValueError):
        return None


def _price(model_bucket: str, tokens: dict, pricing: dict[str, dict[str, float]]) -> float:
    """USD for one tokens breakdown against one external pricing entry.

    tokens carries input/output/cache_creation/cache_read.
    cache_creation bills at the input rate; cache_read at the discounted
    "cached" rate.
    """
    rates = pricing.get(model_bucket)
    if not rates:
        return 0.0
    inp = int(tokens.get("input_tokens") or tokens.get("input") or 0)
    out = int(tokens.get("output_tokens") or tokens.get("output") or 0)
    cc = int(tokens.get("cache_creation_tokens") or tokens.get("cache_creation") or 0)
    cr = int(
        tokens.get("cache_read_tokens")
        or tokens.get("cached_input_tokens")
        or tokens.get("cache_read")
        or 0
    )
    return (
        (inp + cc) * rates["input"]
        + out * rates["output"]
        + cr * rates["cached"]
    ) / 1_000_000


def _claude_value(claude_payload: dict, pricing: dict[str, dict[str, float]]) -> tuple[float, dict, float]:
    """Return (weekly_usd, by_model_usd, session_usd) for Claude.

    Uses 7d weekly.by_model when JSONL detail is present. OAuth-only
    pct-meter responses return zeros (we can't price a percentage).
    """
    if not isinstance(claude_payload, dict) or not claude_payload.get("ok"):
        return 0.0, {}, 0.0

    weekly = claude_payload.get("weekly") or {}
    session = claude_payload.get("session") or {}

    # OAuth-only mode: pct but no input/output split.
    if "input_tokens" not in weekly:
        return 0.0, {}, 0.0

    weekly_by_model = weekly.get("by_model") or {}
    by_model: dict[str, float] = {}

    # The weekly bucket exposes by_model[bucket] = billable total only,
    # not an input/output split. We approximate per-model dollars by
    # scaling the global breakdown by each bucket's billable share.
    total_billable = sum(int(v or 0) for v in weekly_by_model.values()) or 1
    weekly_breakdown = {
        "input": int(weekly.get("input_tokens") or 0),
        "output": int(weekly.get("output_tokens") or 0),
        "cache_creation": int(weekly.get("cache_creation_tokens") or 0),
        "cache_read": int(weekly.get("cache_read_tokens") or 0),
    }
    for bucket_name, billable in weekly_by_model.items():
        share = (int(billable or 0)) / total_billable
        scaled = {k: int(v * share) for k, v in weekly_breakdown.items()}
        # "other" / unknown buckets fall back to sonnet rates.
        price_key = (
            f"claude-{bucket_name}"
            if bucket_name in ("opus", "sonnet", "haiku")
            else "claude-sonnet"
        )
        usd = round(_price(price_key, scaled, pricing), 2)
        if usd > 0:
            by_model[bucket_name] = usd

    weekly_usd = round(sum(by_model.values()), 2)

    # Session: no per-model split at this granularity; price the
    # session aggregate at sonnet-equivalent rates (modal bucket).
    session_breakdown = {
        "input": int(session.get("input_tokens") or 0),
        "output": int(session.get("output_tokens") or 0),
        "cache_creation": int(session.get("cache_creation_tokens") or 0),
        "cache_read": int(session.get("cache_read_tokens") or 0),
    }
    session_usd = round(_price("claude-sonnet", session_breakdown, pricing), 2)

    return weekly_usd, by_model, session_usd


def _gemini_value(gemini_payload: dict, pricing: dict[str, dict[str, float]]) -> float:
    """Gemini today exposes quota-pct only; no tokens to price.

    Returns 0 and the caller stamps "no data". If gemini.py later emits
    weekly.input_tokens etc., this pricing path activates without a
    schema change.
    """
    if not isinstance(gemini_payload, dict) or not gemini_payload.get("ok"):
        return 0.0
    weekly = gemini_payload.get("weekly") or {}
    if "input_tokens" not in weekly:
        return 0.0
    breakdown = {
        "input": int(weekly.get("input_tokens") or 0),
        "output": int(weekly.get("output_tokens") or 0),
    }
    return round(_price("gemini-pro", breakdown, pricing), 2)


def _codex_value(codex_payload: dict, pricing: dict[str, dict[str, float]]) -> float:
    """Codex / ChatGPT API-equivalent USD from JSONL token splits."""
    if not isinstance(codex_payload, dict) or not codex_payload.get("ok"):
        return 0.0
    weekly = codex_payload.get("weekly") or {}
    if "input_tokens" not in weekly:
        return 0.0
    breakdown = {
        "input": int(weekly.get("input_tokens") or 0),
        "output": int(weekly.get("output_tokens") or 0),
        "cached_input_tokens": int(weekly.get("cached_input_tokens") or 0),
    }
    return round(_price("gpt-5.5", breakdown, pricing), 2)


def _codex_credits(codex_payload: dict, credit_rates: dict[str, dict[str, float]], model: str = "gpt-5.5") -> float:
    """Estimate Codex flexible-pricing credits from token splits.

    This is distinct from API-equivalent USD. OpenAI's Codex plan accounting
    reports credits at token-based rates for paid plan families, so exposing
    both avoids confusing dollars with quota credits.
    """
    if not isinstance(codex_payload, dict) or not codex_payload.get("ok"):
        return 0.0
    weekly = codex_payload.get("weekly") or {}
    rates = credit_rates.get(model)
    if not rates:
        return 0.0
    inp = int(weekly.get("input_tokens") or 0)
    cached = int(weekly.get("cached_input_tokens") or 0)
    out = int(weekly.get("output_tokens") or 0)
    return round(
        (inp * rates["input"] + cached * rates["cached"] + out * rates["output"]) / 1_000_000,
        2,
    )


def compute(merged: dict) -> dict:
    """Compute the value block. Pure function over the merged usage dict."""
    financial_model = _load_financial_model()
    pricing = _as_rate_table(financial_model.get("pricing"))
    codex_credit_rates = _as_rate_table(financial_model.get("codex_credit_rates"))
    subscription_cost_monthly = _optional_float(financial_model.get("subscription_cost_monthly"))
    model_available = bool(pricing)

    claude_payload = merged.get("claude") if isinstance(merged, dict) else None
    gemini_payload = merged.get("gemini") if isinstance(merged, dict) else None
    codex_payload  = merged.get("codex")  if isinstance(merged, dict) else None

    by_tool: dict[str, object] = {}
    by_model: dict[str, float] = {}

    claude_7d, claude_by_model, _session_usd = _claude_value(claude_payload or {}, pricing)
    if claude_7d > 0 or claude_by_model:
        by_tool["claude"] = claude_7d
        for m, usd in claude_by_model.items():
            by_model[m] = round(by_model.get(m, 0.0) + usd, 2)
    else:
        by_tool["claude"] = "no data"

    gem_7d = _gemini_value(gemini_payload or {}, pricing)
    by_tool["gemini"] = gem_7d if gem_7d > 0 else "no data"

    cdx_7d = _codex_value(codex_payload or {}, pricing)
    by_tool["codex"] = cdx_7d if cdx_7d > 0 else "no data"
    codex_credits_7d = _codex_credits(codex_payload or {}, codex_credit_rates)

    numeric = [v for v in by_tool.values() if isinstance(v, int | float)]
    total_7d = round(sum(numeric), 2)

    # 30-day extrapolation: rolling 7d window -> 30d ~= 7d * (30/7).
    # Honest label in the note; this is not a true 30d sum.
    total_30d = round(total_7d * (30 / 7), 2)

    multiplier = round(total_30d / subscription_cost_monthly, 2) if subscription_cost_monthly else 0.0

    if not model_available:
        note = (
            "Financial value unavailable: set ECO_VALUE_MODEL_JSON to a JSON export "
            "from the canonical financial model. Tools showing 'no data' either "
            "lack token counts or lack matching pricing rows."
        )
    else:
        note = (
            "USD value loaded from ECO_VALUE_MODEL_JSON. 30d extrapolated from "
            "7d window. Codex credits are separate token-based plan credits, "
            "not USD. Tools showing 'no data' expose only quota % not token counts "
            "or lack matching pricing rows."
        )

    return {
        "total_usd_7d": total_7d,
        "total_usd_30d": total_30d,
        "by_tool": by_tool,
        "by_model": by_model,
        "subscription_cost_monthly": subscription_cost_monthly,
        "multiplier": multiplier,
        "codex_credits_7d": codex_credits_7d,
        "codex_credit_rates": codex_credit_rates,
        "note": note,
    }


if __name__ == "__main__":
    import json
    import sys
    from pathlib import Path
    src = Path.home() / ".eco" / "current" / "usage.json"
    if not src.exists():
        print(f"no usage.json at {src}", file=sys.stderr)
        raise SystemExit(1)
    merged = json.loads(src.read_text())
    print(json.dumps(compute(merged), indent=2))
