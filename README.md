# Mac Doctor

A single-command macOS diagnostic tool that tells you exactly why your Mac is slow.

No dependencies. No telemetry. No data leaves your Mac.

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-crazymahii-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/crazymahii)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/mahii6991?style=flat&logo=github&label=Sponsor&color=ea4aaa)](https://github.com/sponsors/mahii6991)

## Install

### Manual

```bash
git clone https://github.com/mahii6991/mac-doctor.git
cd mac-doctor
sudo make install
```

### One-liner (no install)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mahii6991/mac-doctor/main/mac-doctor.sh)
```

## Usage

```bash
mac-doctor              # standard scan
mac-doctor --fix        # scan + fix issues interactively
mac-doctor --html       # save HTML report to Desktop
mac-doctor --no-snap    # skip snapshot comparison
mac-doctor --free-ram   # what to quit/kill to free RAM for local AI models
```

## Freeing RAM for local models

Running an LLM locally (Ollama, LM Studio, llama.cpp…) and it won't fit in memory?

```bash
mac-doctor --free-ram
```

Shows your free memory, which model sizes fit right now vs. after cleanup, and ranks every candidate by how much RAM it holds and how safe it is to kill:

- **✓ Safe to kill** — browser tab helpers, Node dev servers/watchers, language servers, Docker VM, Spotlight & media indexers, iOS Simulator. These respawn or restart cleanly.
- **? Quit manually** — GUI apps you opened (Slack, Chrome, VS Code…). Listed so you decide; kill them from the prompt too.
- **🔒 Protected** — your LLM runtime, macOS system processes, other users' processes, and this script's own terminal chain are never offered for killing.

Pick items by number (`1 3 5`), `safe` for all ✓ items, `all`, or press Enter to cancel. Kills use SIGTERM so apps get a chance to save, then re-checks your free memory.

```text
  [1]  ✓ Node.js dev servers & watchers            1240 MB    6 procs
  [2]  ✓ Google Chrome helpers                      980 MB   12 procs
  [3]  ? Slack                                      512 MB    3 procs
  🔒 Local LLM runtime                              4700 MB    2 procs

  Can run right now:      ~3-4B models (llama3.2:3b, phi3:mini)
  After freeing pool:     ~7-9B models (llama3.1:8b, mistral:7b)
```

## What it checks

| # | Section | What it detects |
|---|---------|----------------|
| 1 | System Overview | Model, chip, RAM, macOS version, uptime |
| 2 | Pending Updates | Software updates consuming background resources |
| 3 | **AI Tools & Agents** | Running AI tools (Claude, Ollama, LM Studio, Cursor, Copilot), local model storage, Claude Code usage stats |
| 4 | CPU Analysis | Load, top consumers, runaway processes, kernel_task throttling |
| 5 | Memory Analysis | Pressure, swap, pageouts, top memory consumers |
| 6 | Disk Analysis | Usage, I/O, space breakdown (Downloads, Trash, Caches) |
| 7 | Thermal & Power | Throttling, battery health, power state |
| 8 | Sleep Blockers | Processes preventing sleep, draining battery |
| 9 | Security Audit | FileVault, Firewall, SIP, Gatekeeper, XProtect |
| 10 | Background Processes | Login items, LaunchAgents, process count |
| 11 | iCloud Sync | Container status, stalled syncs |
| 12 | Spotlight | Indexing load |
| 13 | Network & WiFi | DNS speed, signal strength, SNR, VPN detection |
| 14 | GPU & Graphics | WindowServer load, open app count |
| 15 | Electron Apps | Per-app RAM/CPU breakdown for Chromium-based apps |
| 16 | Rosetta 2 | x86 apps running under emulation on Apple Silicon |
| 17 | Time Machine | Active backup detection |
| 18 | Kernel Health | Kernel panics, app crashes |
| 19 | Developer Env | Node, JVM, Docker, Xcode DerivedData, Homebrew cache |
| 20 | Storage | Docker images, Mail, Simulators, Application Support |
| 21 | Changes Since Last Run | Drift comparison with previous snapshot |

## Scheduled scans

Mac Doctor can run weekly and send you a macOS notification:

```bash
make schedule
```

Scans run every Sunday at 10 AM. You'll get a notification with your health score and any new issues.

## Uninstall

```bash
# Make / .pkg
make uninstall
# or manually:
sudo rm /usr/local/bin/mac-doctor
rm ~/Library/LaunchAgents/com.macdoctor.scan.plist
sudo rm -rf /usr/local/share/mac-doctor
```

## Building the .pkg installer

```bash
# Unsigned (for testing)
bash packaging/pkg/build-pkg.sh

# Signed + notarized (requires Apple Developer ID)
export APPLE_ID="you@example.com"
export TEAM_ID="YOUR_TEAM_ID"
export APP_PASSWORD="app-specific-password"
bash packaging/pkg/build-pkg.sh --sign "Developer ID Installer: Your Name"
```

## Privacy & Security

- **No telemetry, no data collection.** Nothing about you or your Mac is ever sent anywhere.
- **Minimal network use.** Checks rely on built-in macOS commands (`ps`, `vm_stat`, `sysctl`, `diskutil`, etc.). The only network access is Apple's own update check (`softwareupdate`) and a single DNS lookup used to time your resolver — no personal data is transmitted.
- **No root required.** Runs entirely as your user. `--fix` mode asks for `sudo` only for specific system fixes you approve.
- **Open source.** Read every line of the script — it's one file.
- **Snapshots stay local.** History is stored in `~/.mac-doctor/` on your machine only.

## Requirements

- macOS 12+ (Monterey or later)
- Intel or Apple Silicon
- No root needed for diagnostics

## Support

If Mac Doctor saved you time or fixed your Mac, consider supporting the project:

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-crazymahii-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/crazymahii)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/mahii6991?style=flat&logo=github&label=Sponsor&color=ea4aaa)](https://github.com/sponsors/mahii6991)

## License

MIT
