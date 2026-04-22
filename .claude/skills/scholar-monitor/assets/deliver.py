#!/usr/bin/env python3
"""Delivery dispatcher for scholar-monitor.

Channels supported here: ntfy.sh (push) and SMTP email.
Telegram delivery goes through the Claude Code MCP tool, not this script.

Usage:
    deliver.py ntfy --topic TOPIC --title "…" --body-file PATH [--priority default]
    deliver.py email --to ADDR --subject "…" --body-file PATH \
        --smtp-host HOST --smtp-port PORT --from ADDR [--pass-env VAR]

Exits 0 on success, nonzero on failure. Errors printed to stderr.
"""
from __future__ import annotations

import argparse
import os
import smtplib
import ssl
import sys
import urllib.request
from email.message import EmailMessage


def _log(msg: str) -> None:
    print(f"[deliver] {msg}", file=sys.stderr)


def _read_body(path: str, limit: int | None = None) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        body = fh.read()
    if limit is not None and len(body) > limit:
        body = body[:limit] + f"\n\n[truncated — full file: {path}]"
    return body


def deliver_ntfy(topic: str, title: str, body_file: str,
                 priority: str = "default", click_url: str = "") -> int:
    if not topic:
        _log("ntfy: empty topic — skipping")
        return 2
    # ntfy free tier has a 4 KB body limit for plain POST; use link for long content
    body = _read_body(body_file, limit=3500)
    url = f"https://ntfy.sh/{topic}"
    # HTTP headers are latin-1 by default — replace common Unicode punctuation
    # with ASCII equivalents, then drop any remaining non-ASCII. Body stays UTF-8.
    safe_title = (
        title.replace("—", "-").replace("–", "-")
             .replace("‘", "'").replace("’", "'")
             .replace("“", '"').replace("”", '"')
             .replace("…", "...")
             .encode("ascii", errors="replace").decode("ascii")
    )
    req = urllib.request.Request(
        url,
        data=body.encode("utf-8"),
        method="POST",
        headers={
            "Title": safe_title[:200],
            "Priority": priority,
            "Tags": "books,newspaper",
            **({"Click": click_url} if click_url else {}),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            _log(f"ntfy: status {resp.status}")
        return 0
    except Exception as exc:
        _log(f"ntfy: FAILED — {exc}")
        return 1


def deliver_email(to: str, subject: str, body_file: str,
                  smtp_host: str, smtp_port: int, from_addr: str,
                  pass_env: str = "SMTP_PASS", use_tls: bool = True) -> int:
    if not (to and smtp_host and from_addr):
        _log("email: missing required fields — skipping")
        return 2
    password = os.environ.get(pass_env, "") if pass_env else ""
    body = _read_body(body_file)
    msg = EmailMessage()
    msg["From"] = from_addr
    msg["To"] = to
    msg["Subject"] = subject[:200] or "scholar-monitor digest"
    msg.set_content(body)
    try:
        if use_tls:
            ctx = ssl.create_default_context()
            with smtplib.SMTP(smtp_host, smtp_port, timeout=30) as server:
                server.starttls(context=ctx)
                if password:
                    server.login(from_addr, password)
                server.send_message(msg)
        else:
            with smtplib.SMTP_SSL(smtp_host, smtp_port, timeout=30) as server:
                if password:
                    server.login(from_addr, password)
                server.send_message(msg)
        _log(f"email: sent to {to}")
        return 0
    except Exception as exc:
        _log(f"email: FAILED — {exc}")
        return 1


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="channel", required=True)

    p_ntfy = sub.add_parser("ntfy")
    p_ntfy.add_argument("--topic", required=True)
    p_ntfy.add_argument("--title", required=True)
    p_ntfy.add_argument("--body-file", required=True)
    p_ntfy.add_argument("--priority", default="default",
                        choices=["min", "low", "default", "high", "urgent"])
    p_ntfy.add_argument("--click-url", default="")

    p_email = sub.add_parser("email")
    p_email.add_argument("--to", required=True)
    p_email.add_argument("--subject", required=True)
    p_email.add_argument("--body-file", required=True)
    p_email.add_argument("--smtp-host", required=True)
    p_email.add_argument("--smtp-port", type=int, default=587)
    p_email.add_argument("--from", dest="from_addr", required=True)
    p_email.add_argument("--pass-env", default="SMTP_PASS")
    p_email.add_argument("--no-tls", action="store_true")

    args = ap.parse_args()

    if args.channel == "ntfy":
        return deliver_ntfy(
            topic=args.topic, title=args.title, body_file=args.body_file,
            priority=args.priority, click_url=args.click_url,
        )
    if args.channel == "email":
        return deliver_email(
            to=args.to, subject=args.subject, body_file=args.body_file,
            smtp_host=args.smtp_host, smtp_port=args.smtp_port,
            from_addr=args.from_addr, pass_env=args.pass_env,
            use_tls=not args.no_tls,
        )
    return 2


if __name__ == "__main__":
    sys.exit(main())
