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

Both run at the same time: Firefox runs one process per profile (measured on
Firefox 157). Starting Firefox with Marionette flags *without* a different
profile only opens a window in the running daily instance, and no port opens.

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

## Working with pages

- **Reuse the tab that is already open.** A cold start of `firefox-mcp` opens
  exactly one tab (`about:home`, or the restored session if the profile
  restores one). Run `list_pages`, `select_page` on it and `navigate_page`.
  Use `new_page` only when two tabs are needed at the same time.
- **Do not re-run `firefox-mcp` to check that the instance is up.** With
  Marionette already listening it opens another window (`about:blank`), one
  more tab to clean up. Check the ports instead (Troubleshooting, step 1).
- **Set the viewport before working with desktop apps:**
  `set_viewport_size(1280, 800)`. A narrow window switches responsive apps to
  their mobile layout. Seen with Odoo 20 at 649 px: many2one inputs became
  readonly and opened a full-screen search dialog, and typed text landed in
  another field.
- **Keep the MCP window visible on screen.** A blank page with an empty
  `body.innerText`, a black screenshot and `take_snapshot` failing with
  "Selector not found", while the server answers 200 and the DOM has content,
  means the page is not painting. Discriminator, via `evaluate_script`:

  ```js
  () => new Promise(r => { let f = false; requestAnimationFrame(() => f = true); setTimeout(() => r(f), 1000); })
  ```

  `false` means no frames are being produced. Seen 4 times in one session
  (Odoo 20, GNOME 50 on Wayland): `false` while `visibilityState` was
  `visible` and `document.hasFocus()` was `true`; after the window was put on
  screen the probe gave `true` and the page painted by itself. `select_page`
  on the same tab fixed it twice, not the third time; once `document.hidden`
  was `true` and `select_page` set it to `false`. **Cause not confirmed.**
  Hypothesis: on Wayland, Firefox gets no frame callbacks while its window is
  off screen (covered, minimized or on another workspace). Run the probe
  before and after showing the window the next time it happens. Practical
  consequence: browser-driven work cannot run unattended in the background.
- **Verify important inputs after filling them.** `fill_by_uid` once dropped
  the first character with no error ("OFA Export" saved as "FA Export" in an
  Odoo 20 form; found only by reading the database). Seen once, so it is an
  observation, not a rule. Read the value back with `evaluate_script`; if it
  is wrong, `press_key` `ctrl+a` then `type_text` gave the right value.
- **To replace text in a field that already has some, use `press_key`
  `ctrl+a` on the uid, then `type_text`; not `fill_by_uid`.** `fill_by_uid`
  clears with `el.value = ''`, focuses, then sends keystrokes (read in
  firefox-devtools-mcp 0.10.7). If the page writes its own value back on
  focus, the keystrokes are appended: "4" filled with "1" became "41". Seen in
  a HubSpot form, then reproduced on test pages: a React 18 controlled input
  that sets state in `onFocus` appends; the same input without the `onFocus`
  state change, and a plain HTML input, are replaced correctly. Filling an
  empty field is not affected. Fixed upstream by
  [#228](https://github.com/mozilla/firefox-devtools-mcp/pull/228), not
  released yet: 0.10.7 is the latest on npm (2026-10-30), so keep this
  workaround until a newer version ships.

## Troubleshooting

1. **All tools fail, even `list_pages`.** Check that something listens:
   `ss -tln | grep -E ':(2828|9222)\b'`. Nothing → run `firefox-mcp`.
2. **Ports are up but every tool returns `Error: unknown error`** (up to
   firefox-devtools-mcp 0.10.6; later versions fail fast with "Another WebDriver
   session is already active"). Marionette accepts **one** client. Another MCP
   server (often another Claude Code session) holds it. Find it:
   - `ss -tnp | grep :2828` shows the other `geckodriver` connection;
   - `pgrep -af firefox-devtools-mcp`, then `ps -o ppid= -p <pid>`, leads to the
     owning client; `readlink /proc/<pid>/cwd` tells which project it runs in.

   Asking that session to "stop using it" is not enough: the server keeps its
   session until its idle timeout (30 min; `--idle-timeout` after 0.10.6), and
   reconnects on its next tool call. In the other session run
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
