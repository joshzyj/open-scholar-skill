# Delivery Protocol

Three stackable channels. The skill tries every channel listed in `config.channels`; failures in one channel do **not** block the others. File delivery is always on and cannot be disabled — it's the audit trail and the `digest` mode's source of truth.

## Channel: `file` (always on)

Write the full digest to `output/monitor/feed-YYYY-MM-DD.md`. If a file already exists for today's date, append a `## Run at HH:MM:SS` section rather than overwriting.

```bash
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M:%S)
OUT_DIR="${OUTPUT_ROOT:-output}/monitor"
mkdir -p "$OUT_DIR"
FEED="$OUT_DIR/feed-$DATE.md"
if [ -f "$FEED" ]; then
    printf "\n\n---\n## Run at %s\n\n" "$TIME" >> "$FEED"
fi
# ... append digest content ...
echo "file: wrote $FEED"
```

## Channel: `telegram` (push to phone)

Goes through the Claude Code MCP tool `mcp__plugin_telegram_telegram__reply`, **not** through `deliver.py`. The skill's instructions call the MCP tool directly during Phase 4.

**Prerequisites**:
- User has run `/telegram:configure` at least once
- `~/.claude/scholar-monitor/config.json` has `telegram.chat_id` populated (prompted during `configure delivery`)

**Message pattern** — send a *new* message (not a reply; `reply_to` is omitted):

```
Call mcp__plugin_telegram_telegram__reply with:
    chat_id: <from config.json>
    text:    <short digest — counts per category + top 3 titles, under 4000 chars>
    files:   ["<absolute path to feed-YYYY-MM-DD.md>"]
```

**Long-message handling**: Telegram caps message `text` at 4096 chars. If the digest exceeds that, truncate the message body to a header summary (counts + top items) and rely on the attached file for full content. Do **not** chunk across multiple `reply` calls — that creates notification spam on the user's phone.

**Security**: Telegram's allowlist is managed by `/telegram:access`. scholar-monitor cannot send to an arbitrary `chat_id` that the user hasn't already approved via that skill. If `chat_id` is empty or absent from the allowlist, the MCP call fails cleanly and the skill logs the error to the process log, then continues.

## Channel: `ntfy` (push to phone — alt)

Free zero-auth service. User picks an unguessable topic string and subscribes via the ntfy iOS/Android app (one tap — no account).

**Prerequisites**:
- User has installed the ntfy app and subscribed to topic
- `config.json` has `ntfy.topic` populated

**Setup prompt** during `configure delivery`:

```
A ntfy topic is a random string you'll use as a private channel.
Recommended: generate an unguessable string (16+ chars). Anyone who
knows the string can push to it, so treat it like a shared secret.

Generate one? [Y/n] → openssl rand -hex 8 → "a3f9e4b2d7c18650"
```

**Invocation**:

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-monitor"
TOPIC="$(jq -r '.ntfy.topic // ""' "$SCHOLAR_MONITOR_DIR/config.json")"
FEED="output/monitor/feed-$(date +%Y-%m-%d).md"

if [ -n "$TOPIC" ]; then
    python3 "$SKILL_DIR/assets/deliver.py" ntfy \
        --topic "$TOPIC" \
        --title "scholar-monitor — $NEW_COUNT new papers" \
        --body-file "$FEED" \
        --priority default
fi
```

**Long-message handling**: ntfy free tier caps POST body at ~4 KB. `deliver.py` truncates to 3500 chars and adds a footer pointing to the local file path. Priority defaults to `default`; use `high` for urgent alerts (retraction notices) and `low` for low-signal digests.

## Channel: `email` (optional, advanced)

Only wired up if the user explicitly sets SMTP creds. Skipped during default `configure delivery` — ntfy + Telegram cover 95% of phone-push needs with zero SMTP setup.

**Prerequisites**:
- `config.json.email` fields populated (host, port, from, to, pass_env)
- Environment variable named by `pass_env` is exported in the user's shell

**Invocation**:

```bash
SKILL_DIR="${SCHOLAR_SKILL_DIR:-.}/.claude/skills/scholar-monitor"
CFG="$SCHOLAR_MONITOR_DIR/config.json"
SMTP_HOST=$(jq -r '.email.smtp_host // ""' "$CFG")
SMTP_PORT=$(jq -r '.email.smtp_port // 587' "$CFG")
EMAIL_FROM=$(jq -r '.email.from // ""' "$CFG")
EMAIL_TO=$(jq -r '.email.to // ""' "$CFG")
PASS_ENV=$(jq -r '.email.pass_env // "SMTP_PASS"' "$CFG")

if [ -n "$SMTP_HOST" ] && [ -n "$EMAIL_TO" ]; then
    python3 "$SKILL_DIR/assets/deliver.py" email \
        --to "$EMAIL_TO" \
        --subject "scholar-monitor digest — $(date +%Y-%m-%d)" \
        --body-file "output/monitor/feed-$(date +%Y-%m-%d).md" \
        --smtp-host "$SMTP_HOST" \
        --smtp-port "$SMTP_PORT" \
        --from "$EMAIL_FROM" \
        --pass-env "$PASS_ENV"
fi
```

**Gmail users**: use an App Password (requires 2FA on the account). `SMTP_PASS` stored as an environment variable, never in `config.json`.

## `config.json` Full Schema

```json
{
  "version": "1.0",
  "channels": ["file", "telegram"],
  "telegram": { "chat_id": "" },
  "ntfy":     { "topic": "" },
  "email": {
    "smtp_host": "",
    "smtp_port": 587,
    "from": "",
    "to": "",
    "pass_env": "SMTP_PASS"
  }
}
```

- `channels` — ordered list of channels to try. File is prepended automatically if missing.
- File permissions: written with `chmod 0600` to protect the chat_id and any SMTP details.

## Failure Discipline

- Each channel's success/failure is logged to the process log as a separate row.
- One channel failing does **not** prevent other channels from running.
- All channels failing does **not** fail the skill run — file delivery has already succeeded.
- Knowledge-graph ingest (Phase 5) runs regardless of delivery outcome.

## Debugging

```bash
# Dry-run a channel without touching delivery
python3 "$SKILL_DIR/assets/deliver.py" ntfy \
    --topic "test-topic-localhost" \
    --title "test" \
    --body-file /tmp/test-body.md

# Subscribe to ntfy from the command line to see messages without the phone app
curl -s "https://ntfy.sh/$TOPIC/json"
```
