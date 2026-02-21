# 🩺 Mac Doctor

A single bash script that tells you exactly why your Mac is slow.

No dependencies. No install. Just run it.

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-crazymahii-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/crazymahii)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/mahii6991?style=flat&logo=github&label=Sponsor&color=ea4aaa)](https://github.com/sponsors/mahii6991)

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

## Support

If Mac Doctor saved you time or fixed your Mac, consider buying me a coffee!

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-crazymahii-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/crazymahii)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/mahii6991?style=flat&logo=github&label=Sponsor&color=ea4aaa)](https://github.com/sponsors/mahii6991)

## License

MIT
