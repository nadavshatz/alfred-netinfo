# Network Info for Alfred

Your local and external IP and MAC addresses, from Alfred.

| Keyword | Shows |
|---|---|
| `ip`  | Local IP per interface, plus your external IP |
| `mac` | MAC address per hardware port |

↩ pastes into the front app · ⌘↩ copies to the clipboard.

## Security

- Pure zsh + tools that ship with macOS. No Ruby, Python or Homebrew at runtime.
- The external IP is fetched over HTTPS only (`curl --proto =https --tlsv1.2`,
  3 s timeout) from `https://api.ipify.org` by default; the service is
  configurable but must be `https://`, and the answer is shown only if it is a
  bare IPv4/IPv6 address.
- Interface names are validated before being passed to `ipconfig`/`networksetup`
  as a single argument; nothing is evaluated by a shell.
- Updates come from this repo's GitHub Releases and are checked against the
  release's SHA-256, bundle id and version before Alfred is asked to install.

VPN tunnels (`utun*`) are not network services and are not listed.

## Development

```sh
zsh tests/run_tests.sh       # mocked test-suite (zsh + jq)
zsh tests/build_test.sh      # packaging test
zsh scripts/build.sh         # dist/Network-Info-<version>.alfredworkflow
python3 scripts/make_plist.py && swift scripts/make_icons.swift   # regenerate
```
