# Mac Doctor

A single-command macOS diagnostic tool that tells you exactly why your Mac is slow.

No dependencies. No telemetry. No data leaves your Mac.

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-crazymahii-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/crazymahii)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/mahii6991?style=flat&logo=github&label=Sponsor&color=ea4aaa)](https://github.com/sponsors/mahii6991)

## Install

### Homebrew (recommended)

```bash
brew tap mahii6991/tap
brew install mac-doctor
```

### .pkg installer

Download the latest `.pkg` from [Releases](https://github.com/mahii6991/mac-doctor/releases) and double-click to install. Signed and notarized by Apple — no Gatekeeper warnings.

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
# Via Homebrew
brew services start mac-doctor

# Via Make
make schedule
```

Scans run every Sunday at 10 AM. You'll get a notification with your health score and any new issues.

## Uninstall

```bash
# Homebrew
brew uninstall mac-doctor && brew untap mahii6991/tap

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

- **No network calls.** Every check uses built-in macOS commands (`ps`, `vm_stat`, `sysctl`, `diskutil`, etc.)
- **No telemetry.** Nothing is sent anywhere. Ever.
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
