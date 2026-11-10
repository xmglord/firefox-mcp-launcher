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
- **Keep part of the MCP window uncovered on screen.** Firefox paints the
  page only while some part of its window is on screen. Symptoms when it
  does not: a blank page with an empty `body.innerText`, a black screenshot,
  `take_snapshot` failing with "Selector not found" while the server answers
  200 and the DOM has content, or dropdowns opening with their options laid
  out far off the viewport. Probe, via `evaluate_script`:

  ```js
  () => new Promise(r => { let n = 0; const loop = () => { n++; requestAnimationFrame(loop); }; requestAnimationFrame(loop); setTimeout(() => r({ frames: n, hidden: document.hidden }), 1000); })
  ```

  The page is usable only with `hidden: false` and tens of frames (60-80
  when painting normally). Count frames instead of checking that one fired:
  a hidden window still gets 1-3 throttled frames per second, so a boolean
  "did rAF fire" probe reads `true` on a page that is not painting. Check
  both values, because they disagree. Measured with a page sampling both every
  second while the window was moved by hand (Firefox 157, GNOME 50 on
  Wayland, focus in another window throughout):

  | MCP window | `hidden` | Painting |
  |---|---|---|
  | Side by side with another window, or half covered by it | `false` | yes |
  | Full screen (F11), behind a maximized window | `false` | yes |
  | Covered completely by another window (half-width, maximized or full screen) | `true` or `false` | no |
  | Minimized | `true` | no |

  When fully covered, `hidden` was `true` in some runs and `false` in others
  under the same layout (both seen with two maximized windows), but painting
  stopped every time. So the rule is coverage, not focus or window mode: full
  screen only helps because a maximized window leaves the top bar strip
  uncovered; behind another full-screen window it stopped painting too. Other
  workspaces were not measured on their own. Keyboard input is unreliable
  while the page does not paint: on a listbox that opens with an animation,
  the same two `ArrowUp` presses moved one option in one run and did not
  open the list in another (2 of 2 wrong, 3 of 3 right with the window
  uncovered), so `Enter` would have saved the wrong value. Read the focused
  option back before confirming. `document.hasFocus()` was `true` in every sample, minimized included, so it
  says nothing about the window. `select_page` did not change the state (2
  of 2: once hidden, once visible without painting); in an earlier session it
  seemed to help twice, which these tests do not explain. Practical
  consequence: tile the MCP window next to the window you work in while the
  agent drives it; browser-driven work cannot run unattended in the
  background.
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
