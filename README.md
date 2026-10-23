# firefox-mcp-launcher

Run the [Firefox DevTools MCP](https://github.com/mozilla/firefox-devtools-mcp) server against a
**dedicated Firefox instance**, side by side with your everyday browser.

The MCP server's `--connect-existing` mode attaches to a Firefox started with Marionette and
WebDriver BiDi. Marionette sets `navigator.webdriver = true`, so a browser launched that way trips
anti-bot checks, and upstream advises against pointing the server at your regular profile. This repo
keeps the two apart. A small wrapper starts a separate profile, in its own process, with both
protocols on. Your daily Firefox keeps running untouched.

```
 daily Firefox ─ your profile, no Marionette        (normal browsing, logins)

 MCP Firefox ── dedicated profile, --new-instance
     ├─ Marionette        127.0.0.1:2828  ◄── firefox-devtools-mcp --connect-existing
     └─ Remote Agent/BiDi 127.0.0.1:9222  ◄──┘   (navigation, console, network)
```

## What is in here

| Path | What it does |
|---|---|
| `bin/firefox-mcp` | Starts the MCP instance. If it is already up (2828 answers), it only opens a window or URLs in it. It never starts a second instance. |
| `firefox-mcp.desktop` | "Firefox (MCP)" menu entry, so no terminal is needed. |
| `install.sh` | Links the wrapper into `~/.local/bin` and installs the menu entry. No root; safe to re-run. |
| `skill/SKILL.md` | Optional Claude Code skill with the operating notes and the troubleshooting below. |

## Install

```sh
git clone https://github.com/xmglord/firefox-mcp-launcher.git
cd firefox-mcp-launcher
./install.sh                      # add --with-skill to link the Claude Code skill
firefox-mcp --create-profile      # clean, dedicated profile; path saved to the config
```

Register the MCP server (Claude Code shown; any MCP client takes the same command):

```sh
claude mcp add --scope user firefox-devtools -- \
  npx -y @mozilla/firefox-devtools-mcp@latest --connect-existing --marionette-port 2828
```

Start the instance with `firefox-mcp` or the menu entry, then ask the agent to list pages.

## Configuration

| Setting | Default |
|---|---|
| Profile directory | first non-comment line of `${XDG_CONFIG_HOME:-~/.config}/firefox-mcp/profile`, or `$FIREFOX_MCP_PROFILE` |
| Firefox executable | `$FIREFOX_BIN`, else `firefox` from `PATH` |
| BiDi port | `$FIREFOX_MCP_BIDI_PORT`, else 9222 |
| Marionette port | 2828. It is a profile pref (`marionette.port`), not a flag. If you change it, also change `--marionette-port` in the MCP command. |

`firefox -CreateProfile` exits with 0 even when it fails, so `--create-profile` checks that the
directory exists before saving it. It lets Firefox choose the location: a snap Firefox cannot write
to hidden directories in `$HOME`, so a path such as `~/.local/share/...` fails there. On Firefox 157
it was put in a profile group of its own, so expect it to be missing from your daily profile's
switcher. That does not matter: it is launched by path.

## Security

The default profile is **empty**: no logins, no history. Every page the agent opens is untrusted
input that can try to steer it (prompt injection). In a profile with your sessions, a successful
injection acts as you.

If you need the agent to work behind a login, sign in to that one site inside the MCP profile.
Do not clone your daily profile: a clone carries every session, which is what upstream's "use a
dedicated profile" warning is about.

## Troubleshooting

- **Every tool fails, even listing pages.** Nothing listens on 2828: run `firefox-mcp`.
  `--connect-existing` never launches Firefox.
- **Ports are up, but every tool returns `Error: unknown error`.** Marionette accepts only one
  client, so another MCP server (for example, a second agent session) is attached.
  `ss -tnp | grep :2828` shows that connection. Disable the server in the other client, then
  reconnect in yours. A client that only "stops using it" reconnects as soon as the port is free.
- **Navigation fails with an error ending in `reading 'replace'`.** Firefox was started without
  `--remote-debugging-port`, probably by hand. Close it and use `firefox-mcp`.
- **Captchas in the MCP instance** are expected (`navigator.webdriver = true`). Use your daily
  browser for those sites.

## Compatibility

Tested on Ubuntu 26.04 with the Firefox 157 snap. The Debian/RPM packages, the tarball and the
Flatpak should work: the wrapper only needs `firefox` (or `$FIREFOX_BIN`) and a profile path, and
`--create-profile` also searches their profile roots. But they are **not tested**. Reports welcome.

## License

MIT
