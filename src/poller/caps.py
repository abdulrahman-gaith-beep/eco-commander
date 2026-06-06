"""
Generic usage-window constants.

Tracked source intentionally ships neutral, non-operator defaults. Vendors
publish reset-window behavior for usage surfaces, but account-specific token
caps can vary and should not be recorded in public source. Local deployments
that need calibrated caps should keep those values in untracked local config.

The Claude usage surface has three relevant meters:

    1. 5-hour rolling, all models pooled (session)
    2. 7-day, all models pooled
    3. 7-day, Sonnet-only sub-bucket

The weekly headline uses the most-saturated weekly bucket.
"""

# Neutral non-zero placeholder. Keep this at 1 so v0.x estimators do not divide
# by zero before local/private configuration supplies calibrated limits.
UNKNOWN_TOKEN_CAP = 1


def is_unknown_token_cap(cap: object) -> bool:
    """Return True when a configured token cap is the public unknown sentinel."""
    return cap == UNKNOWN_TOKEN_CAP

CLAUDE_DEFAULT_5H_TOKENS = UNKNOWN_TOKEN_CAP
CLAUDE_DEFAULT_7D_ALL_TOKENS = UNKNOWN_TOKEN_CAP
CLAUDE_DEFAULT_7D_SONNET_TOKENS = UNKNOWN_TOKEN_CAP

# cache_read counts toward quota at this fraction of input rate.
# Anthropic explicitly states: "Tokens read from cache do not count towards
# your token rate limits."
CACHE_READ_WEIGHT = 0.00

# Back-compat aliases for older imports. Values remain neutral defaults.
CLAUDE_MAX20X_5H_TOKENS = CLAUDE_DEFAULT_5H_TOKENS
CLAUDE_MAX20X_7D_ALL_TOKENS = CLAUDE_DEFAULT_7D_ALL_TOKENS
CLAUDE_MAX20X_7D_SONNET_TOKENS = CLAUDE_DEFAULT_7D_SONNET_TOKENS
CLAUDE_MAX20X_SESSION_TOKENS = CLAUDE_DEFAULT_5H_TOKENS
CLAUDE_MAX20X_WEEKLY_TOKENS = CLAUDE_DEFAULT_7D_ALL_TOKENS

CODEX_DEFAULT_SESSION_TOKENS = UNKNOWN_TOKEN_CAP
CODEX_DEFAULT_WEEKLY_TOKENS = UNKNOWN_TOKEN_CAP

# Back-compat aliases for older imports. Values remain neutral defaults.
CODEX_PRO_SESSION_TOKENS = CODEX_DEFAULT_SESSION_TOKENS
CODEX_PRO_WEEKLY_TOKENS = CODEX_DEFAULT_WEEKLY_TOKENS

# Window definitions
SESSION_WINDOW_SECONDS = 5 * 3600
WEEKLY_WINDOW_SECONDS = 7 * 24 * 3600

# Color / alert thresholds
WARN_PCT = 80
CRIT_PCT = 95
