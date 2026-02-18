# 🩺 Mac Doctor

A single bash script that tells you exactly why your Mac is slow.

No dependencies. No install. Just run it.

## Run

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mahii6991/mac-doctor/main/mac-doctor.sh)
```

## Flags

```bash
./mac-doctor.sh          # standard scan
./mac-doctor.sh --fix    # scan + fix issues interactively
./mac-doctor.sh --html   # save HTML report to Desktop
```

## What it checks

- CPU, memory, disk, thermals, battery
- Sleep blockers, security (FileVault, Firewall, SIP)
- Electron apps grouped by RAM usage
- iCloud sync, Spotlight, Time Machine
- WiFi signal quality, DNS speed
- Developer tools (Node, Docker, Xcode, Homebrew)
- History tracking — shows what changed since last run

## Requirements

- macOS 12+ · Intel or Apple Silicon · No root needed

## License

MIT
