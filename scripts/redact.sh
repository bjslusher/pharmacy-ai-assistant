#!/usr/bin/env bash
# Shared redaction helpers — source from other scripts.
# Never print secret access keys or session tokens.
#
# Opt-in full identity (local debug only):
#   AWS_PREFLIGHT_SHOW_IDENTITY=1
#   or SHOW_IDENTITY=1

if [[ -n "${_PHARM_REDACT_LOADED:-}" ]]; then
  return 0 2>/dev/null || true
fi
_PHARM_REDACT_LOADED=1

SHOW_IDENTITY="${AWS_PREFLIGHT_SHOW_IDENTITY:-${SHOW_IDENTITY:-0}}"

mask_account() {
  local a="${1:-}"
  [[ -z "$a" ]] && { echo "(unknown)"; return; }
  [[ "$SHOW_IDENTITY" == "1" ]] && { echo "$a"; return; }
  local n=${#a}
  [[ "$n" -le 4 ]] && { echo "****"; return; }
  echo "****${a: -4}"
}

mask_arn() {
  local arn="${1:-}"
  [[ -z "$arn" ]] && { echo "(unknown)"; return; }
  [[ "$SHOW_IDENTITY" == "1" ]] && { echo "$arn"; return; }
  python3 - "$arn" <<'PY'
import re, sys
arn = sys.argv[1]
m = re.match(r"^(arn:aws:iam::)(\d{12})(:.+)$", arn)
if not m:
    print(arn[:12] + "…" + arn[-6:] if len(arn) > 16 else "***")
    raise SystemExit
prefix, acct, rest = m.group(1), m.group(2), m.group(3)
masked_acct = "****" + acct[-4:]
m2 = re.match(r"^:(user|role|assumed-role)/(.+)$", rest)
if m2:
    kind, name = m2.group(1), m2.group(2)
    short = (name[0] + "***") if name else "***"
    print(f"{prefix}{masked_acct}:{kind}/{short}")
else:
    print(f"{prefix}{masked_acct}:***")
PY
}

mask_access_key_id() {
  local k="${1:-}"
  [[ -z "$k" ]] && { echo "(none)"; return; }
  # Never print full key id even with SHOW_IDENTITY — only partial
  echo "${k:0:4}************${k: -4}"
}

# Scrub a free-form log line (keys, long base64-ish secrets)
redact_line() {
  local line="$*"
  # Access key ids
  line=$(echo "$line" | sed -E 's/AKIA[A-Z0-9]{16}/AKIA************/g; s/ASIA[A-Z0-9]{16}/ASIA************/g')
  # 12-digit AWS account ids standing alone or after account=
  line=$(echo "$line" | sed -E 's/\b([0-9]{8})([0-9]{4})\b/****\2/g')
  # IAM ARNs — keep structure, mask account + name
  line=$(echo "$line" | sed -E 's#(arn:aws:iam::)[0-9]{12}(:user/)[A-Za-z0-9+=,.@_-]+#\1****XXXX\2X***#g')
  line=$(echo "$line" | sed -E 's#(arn:aws:iam::)[0-9]{12}(:role/)[A-Za-z0-9+=,.@_-]+#\1****XXXX\2X***#g')
  echo "$line"
}
