---
name: firefox-mcp
description: Run and troubleshoot the Firefox DevTools MCP server against a dedicated Firefox instance launched by the firefox-mcp wrapper (Marionette on 2828, WebDriver BiDi on 9222, separate from the daily browser). Use it to drive the browser through MCP, to start or reconnect the MCP instance, or to diagnose failing browser tools.
when_to_use: Triggers on "Firefox", "browser", "Marionette", "WebDriver BiDi", "Remote Agent", "port 2828", "port 9222", "captcha", "Cloudflare", "navigator.webdriver", or when an `mcp__firefox-devtools__*` tool fails.
---

# Firefox DevTools MCP with a dedicated instance

The MCP server is registered with `--connect-existing --marionette-port 2828`:
**it does not launch Firefox.** It attaches to a Firefox that is already
listening on 2828. If none is running, every tool fails. Start one with
`firefox-mcp` (or the "Firefox (MCP)" menu entry) and retry.

## Layout

| Instance | Profile | Marionette | Use |
|---|---|---|---|
| Daily | your normal profile | off | real browsing, logins |
| MCP | dedicated profile (`firefox-mcp --print-profile`) | on, 2828; BiDi on 9222 | driven by the agent |

Both run at the same time: they are different profiles, and `--new-instance`
keeps the MCP one from being folded into the daily process.

## Why it is split

- Marionette sets `navigator.webdriver = true`. Anti-bot checks
  (Cloudflare/Turnstile and similar) react with captcha loops, so it stays off
  the daily profile. **Captchas in the MCP instance are expected.**
- Marionette starts only with `--marionette` or `MOZ_MARIONETTE=1`; the
  `marionette.enabled` pref alone does not start the server. That is why a
  wrapper is needed and a profile setting is not enough.
- `--remote-debugging-port` is not optional. Without the Remote Agent,
  `navigate_page`/`new_page` fail with an error ending in `reading 'replace'`
  (selenium reads a `webSocketUrl` capability Firefox
  never returned), and console/network tools report "Remote Agent not running".
- The dedicated profile has no logins by default. Pages the agent opens can
  carry prompt injection; keep sessions that matter out of reach of the agent.

## Troubleshooting

1. **All tools fail, even `list_pages`.** Check that something listens:
   `ss -tln | grep -E ':(2828|9222)\b'`. Nothing → run `firefox-mcp`.
2. **Ports are up but every tool returns `Error: unknown error`.** Marionette
   accepts **one** client. Another MCP server (often another Claude Code
   session) holds it. Find it:
   - `ss -tnp | grep :2828` shows the other `geckodriver` connection;
   - `pgrep -af firefox-devtools-mcp`, then `ps -o ppid= -p <pid>`, leads to the
     owning client; `readlink /proc/<pid>/cwd` tells which project it runs in.

   Asking that session to "stop using it" is not enough: its server reconnects
   as soon as the port is free and wins the race. In the other session run
   `/mcp` → `firefox-devtools` → **Disable** (or close it), then `/mcp` →
   Reconnect here. Do not kill another session's processes.
3. **After restarting the MCP browser,** `--connect-existing` reconnects once
   Marionette is back on 2828. If it does not, `/mcp` → Reconnect.
4. **`navigate_page` fails with "reading 'replace'".** The instance was started
   without `--remote-debugging-port`, probably launched by hand. Close it and
   start it with `firefox-mcp`.
5. **A save in a web form looks like it did nothing.** Some sites confirm
   several seconds after the click. Wait, then take a screenshot or re-read the
   page before concluding the click failed.
