#!/bin/bash
# ============================================================================
# Mac Doctor - Granular macOS Performance Diagnostics
# ============================================================================
# Analyzes your Mac at every level to find exactly what's slowing it down.
# No dependencies required — uses only built-in macOS tools.
#
# Usage:
#   ./mac-doctor.sh             Standard diagnostic
#   ./mac-doctor.sh --fix       Diagnostic + interactive fixes at the end
#   ./mac-doctor.sh --html      Save a self-contained HTML report to Desktop
#   ./mac-doctor.sh --no-snap   Skip snapshot comparison (don't read/write history)
# ============================================================================

set +e

# ── CLI Flag Parsing ──────────────────────────────────────────────────────────
DO_FIX=false
DO_HTML=false
DO_SNAP=true

for _arg in "$@"; do
    case "$_arg" in
        --fix)     DO_FIX=true ;;
        --html)    DO_HTML=true ;;
        --no-snap) DO_SNAP=false ;;
        --help)
            echo "Mac Doctor — Granular macOS Performance Diagnostics"
            echo ""
            echo "Usage: mac-doctor [--fix] [--html] [--no-snap]"
            echo "  --fix      Offer to apply safe fixes after diagnosis"
            echo "  --html     Save an HTML report to ~/Desktop"
            echo "  --no-snap  Skip snapshot save/compare"
            exit 0 ;;
    esac
done

# ── Colors & Formatting ───────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

CRITICAL="${RED}[CRITICAL]${RESET}"
WARNING="${YELLOW}[WARNING]${RESET}"
OK="${GREEN}[OK]${RESET}"
INFO="${CYAN}[INFO]${RESET}"

# ── Global State ──────────────────────────────────────────────────────────────
ISSUES_FOUND=0
WARNINGS_FOUND=0

# Findings accumulator — collects all issues/warnings for ranked summary
# Format: "severity|section|message" (severity: 2=critical, 1=warning)
FINDINGS=""
CURRENT_SECTION=""

# Fix queue — indexed array of "label|command" strings (bash 3.2 safe)
FIX_ACTIONS=()
FIX_COUNT=0

# HTML accumulator
HTML_BODY=""

# Apple Silicon flag (set in Section 1)
IS_APPLE_SILICON=false

# Snapshot state
SNAP_LOADED=false

# Health Score (calculated in final summary)
HEALTH_SCORE=100
SCORE_BADGE_CLASS="b-ok"

# CURRENT_* variables captured during sections, written to snapshot at end
CURRENT_mem_pct=0
CURRENT_disk_pct=0
CURRENT_swap_mb=0
CURRENT_pageouts=0
CURRENT_cpu_load=0
CURRENT_processes=0

# ── Snapshot System ───────────────────────────────────────────────────────────
SNAP_DIR="$HOME/.mac-doctor"
SNAP_FILE="$SNAP_DIR/snapshot.txt"

# Snapshot variables (populated by load_snapshot via dot-source)
SNAP_TIMESTAMP=0; SNAP_issues=0; SNAP_warnings=0
SNAP_mem_pct=0;   SNAP_disk_pct=0; SNAP_swap_mb=0
SNAP_pageouts=0;  SNAP_cpu_load=0; SNAP_processes=0

load_snapshot() {
    [ "$DO_SNAP" = "true" ] || return
    [ -f "$SNAP_FILE" ]     || return
    # shellcheck disable=SC1090
    . "$SNAP_FILE"
    SNAP_LOADED=true
}

save_snapshot() {
    [ "$DO_SNAP" = "true" ] || return
    mkdir -p "$SNAP_DIR"
    {
        printf 'SNAP_TIMESTAMP=%s\n' "$(date +%s)"
        printf 'SNAP_issues=%s\n'    "$ISSUES_FOUND"
        printf 'SNAP_warnings=%s\n'  "$WARNINGS_FOUND"
        printf 'SNAP_mem_pct=%s\n'   "$CURRENT_mem_pct"
        printf 'SNAP_disk_pct=%s\n'  "$CURRENT_disk_pct"
        printf 'SNAP_swap_mb=%s\n'   "$CURRENT_swap_mb"
        printf 'SNAP_pageouts=%s\n'  "$CURRENT_pageouts"
        printf 'SNAP_cpu_load=%s\n'  "$CURRENT_cpu_load"
        printf 'SNAP_processes=%s\n' "$CURRENT_processes"
    } > "$SNAP_FILE"
}

# ── Helper Functions ──────────────────────────────────────────────────────────

# HTML side-effects: rows accumulate in HTML_BODY
_html_row() {
    [ "$DO_HTML" = "true" ] || return
    local cls="$1"
    local msg
    msg=$(printf '%s' "$2" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    HTML_BODY="${HTML_BODY}<tr class=\"${cls}\"><td>${msg}</td></tr>"$'\n'
}

_html_section_open() {
    [ "$DO_HTML" = "true" ] || return
    HTML_BODY="${HTML_BODY}<section id=\"sec${1}\"><h2>${1}. ${2}</h2><table class=\"metrics\">"$'\n'
}

_html_section_close() {
    [ "$DO_HTML" = "true" ] || return
    HTML_BODY="${HTML_BODY}</table></section>"$'\n'
}

separator() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}  $1${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    # Track current section name for findings
    CURRENT_SECTION="$1"
}

issue() {
    echo -e "  ${CRITICAL} $1"
    _html_row "critical" "[CRITICAL] $1"
    ISSUES_FOUND=$(( ISSUES_FOUND + 1 ))
    # Strip ANSI codes from message for findings list
    local clean_msg
    clean_msg=$(echo "$1" | sed 's/\\033\[[0-9;]*m//g; s/\x1b\[[0-9;]*m//g')
    FINDINGS="${FINDINGS}2|${CURRENT_SECTION}|${clean_msg}"$'\n'
}

warn() {
    echo -e "  ${WARNING} $1"
    _html_row "warn" "[WARNING] $1"
    WARNINGS_FOUND=$(( WARNINGS_FOUND + 1 ))
    local clean_msg
    clean_msg=$(echo "$1" | sed 's/\\033\[[0-9;]*m//g; s/\x1b\[[0-9;]*m//g')
    FINDINGS="${FINDINGS}1|${CURRENT_SECTION}|${clean_msg}"$'\n'
}

ok() {
    echo -e "  ${OK} $1"
    _html_row "ok" "[OK] $1"
}

info() {
    echo -e "  ${INFO} $1"
    _html_row "info" "$1"
}

bar_chart() {
    local value=$1 max=$2 width=30
    local filled=$(( value * width / max ))
    (( filled > width )) && filled=$width
    local empty=$(( width - filled ))
    local color="${GREEN}"
    if   (( value * 100 / max > 80 )); then color="${RED}"
    elif (( value * 100 / max > 60 )); then color="${YELLOW}"
    fi
    printf "  ${color}["
    printf '%0.s█' $(seq 1 $filled 2>/dev/null) || true
    printf '%0.s░' $(seq 1 $empty  2>/dev/null) || true
    local pct=$(( value * 100 / max ))
    (( pct > 100 )) && pct=100
    printf "]${RESET} %d%%\n" "$pct"
}

add_fix() {
    FIX_ACTIONS[$FIX_COUNT]="$1"
    FIX_COUNT=$(( FIX_COUNT + 1 ))
}

# Show drift vs snapshot for a single numeric metric.
# Usage: show_drift current snap_value unit
# Prints a dim inline annotation if snapshot exists and value differs.
show_drift() {
    local cur="$1" prev="$2" unit="${3:-}"
    [ "$SNAP_LOADED" = "true" ] || return
    [ -z "$prev" ] || [ "$prev" = "0" ] && return
    local diff=$(( cur - prev ))
    if   (( diff > 0 )); then echo -e "  ${DIM}  ↑ was ${prev}${unit} last run (+${diff}${unit})${RESET}"
    elif (( diff < 0 )); then echo -e "  ${DIM}  ↓ was ${prev}${unit} last run (${diff}${unit})${RESET}"
    fi
}

# ── HTML Report Generator ─────────────────────────────────────────────────────
generate_html_report() {
    local report_date
    report_date=$(date +%Y-%m-%d)
    local report_file="$HOME/Desktop/mac-doctor-${report_date}.html"

    cat > "$report_file" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Mac Doctor Report — ${report_date}</title>
<style>
  :root{--bg:#0f0f1a;--card:#1a1a2e;--border:#2a2a4a;--text:#e0e0f0;--dim:#888899;
        --crit:#ff4757;--warn:#ffa502;--ok:#2ed573;--info:#1e90ff;--acc:#7c4dff}
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:var(--bg);color:var(--text);font-family:'SF Mono',Menlo,monospace;
       font-size:13px;line-height:1.6;padding:24px}
  h1{color:var(--acc);font-size:22px;margin-bottom:6px}
  h2{color:var(--info);font-size:13px;text-transform:uppercase;letter-spacing:1px;margin-bottom:10px}
  .meta{color:var(--dim);margin-bottom:20px;font-size:12px}
  .badges{display:flex;gap:10px;flex-wrap:wrap;margin:16px 0 24px}
  .badge{padding:6px 14px;border-radius:5px;font-weight:700;font-size:13px}
  .b-crit{background:#2a000a;color:var(--crit)}.b-warn{background:#1a1000;color:var(--warn)}
  .b-ok{background:#001a08;color:var(--ok)}.b-info{background:#001028;color:var(--info)}
  section{background:var(--card);border:1px solid var(--border);border-radius:8px;
          padding:16px;margin-bottom:14px}
  table{width:100%;border-collapse:collapse}
  td{padding:3px 6px;border-bottom:1px solid var(--border);vertical-align:top}
  tr.critical td{color:var(--crit)} tr.warn td{color:var(--warn)}
  tr.ok td{color:var(--ok)} tr.info td{color:var(--dim)}
  #toc{background:var(--card);border:1px solid var(--border);border-radius:8px;
       padding:14px;margin-bottom:16px;columns:2}
  #toc a{color:var(--info);text-decoration:none;display:block;padding:1px 0;font-size:12px}
  #toc a:hover{color:var(--acc)}
  .footer{margin-top:24px;color:var(--dim);font-size:11px;text-align:center}
</style>
</head>
<body>
<h1>🩺 Mac Doctor Report</h1>
<div class="meta">Generated: ${report_date} $(date +%H:%M:%S) &nbsp;|&nbsp; Host: $(hostname -s) &nbsp;|&nbsp; macOS ${os_version}</div>
<div class="badges">
  <span class="badge b-crit">⚠ ${ISSUES_FOUND} Critical</span>
  <span class="badge b-warn">⚡ ${WARNINGS_FOUND} Warnings</span>
  <span class="badge ${SCORE_BADGE_CLASS}">♥ Health Score: ${HEALTH_SCORE}/100</span>
  <span class="badge b-ok">${hw_model}</span>
  <span class="badge b-info">${cpu_brand} · ${total_ram_gb}GB RAM</span>
</div>
<div id="toc"><strong>Sections</strong><br>
<a href="#sec1">1. System Overview</a><a href="#sec2">2. Pending Updates</a>
<a href="#sec3">3. AI Tools &amp; Agents</a><a href="#sec4">4. CPU Analysis</a>
<a href="#sec5">5. Memory Analysis</a><a href="#sec6">6. Disk Analysis</a>
<a href="#sec7">7. Thermal &amp; Power</a><a href="#sec8">8. Sleep Blockers</a>
<a href="#sec9">9. Security Audit</a><a href="#sec10">10. Background Processes</a>
<a href="#sec11">11. iCloud Sync</a><a href="#sec12">12. Spotlight</a>
<a href="#sec13">13. Network &amp; WiFi</a><a href="#sec14">14. GPU &amp; Graphics</a>
<a href="#sec15">15. Electron Apps</a><a href="#sec16">16. Rosetta 2</a>
<a href="#sec17">17. Time Machine</a><a href="#sec18">18. Kernel Health</a>
<a href="#sec19">19. Developer Env</a><a href="#sec20">20. Storage</a>
<a href="#sec21">21. Changes vs Last Run</a>
</div>
${HTML_BODY}
<div class="footer">Mac Doctor &nbsp;|&nbsp; Run again: <code>./mac-doctor.sh --fix --html</code></div>
</body></html>
HTMLEOF

    echo ""
    ok "HTML report saved: ${report_file}"
    open "$report_file" 2>/dev/null || true
}

# ════════════════════════════════════════════════════════════════════════════
# STARTUP
# ════════════════════════════════════════════════════════════════════════════
load_snapshot
clear

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║                    🩺  Mac Doctor  v2.1                     ║"
echo "  ║           Granular macOS Performance Diagnostics            ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  ${DIM}Scanning your Mac... This may take 20-40 seconds.${RESET}"
echo -e "  ${DIM}Date: $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
[ "$DO_FIX"  = "true" ] && echo -e "  ${GREEN}[Fix mode ON]${RESET}"
[ "$DO_HTML" = "true" ] && echo -e "  ${GREEN}[HTML export ON]${RESET}"
[ "$SNAP_LOADED" = "true" ] && echo -e "  ${DIM}Comparing with snapshot from $(date -r "$SNAP_FILE" '+%Y-%m-%d %H:%M' 2>/dev/null || echo 'previous run')${RESET}"

# ════════════════════════════════════════════════════════════════════════════
# 1. SYSTEM OVERVIEW
# ════════════════════════════════════════════════════════════════════════════
separator "1. SYSTEM OVERVIEW"
_html_section_open 1 "System Overview"

hw_model=$(sysctl -n hw.model 2>/dev/null || echo "Unknown")
total_ram_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
total_ram_gb=$(( total_ram_bytes / 1073741824 ))
os_version=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "?")
uptime_str=$(uptime | sed 's/.*up //' | sed 's/,.*//')

# Apple Silicon vs Intel — machdep.cpu.brand_string is empty on M-series
cpu_brand=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "")
if [ -z "$cpu_brand" ]; then
    cpu_brand=$(system_profiler SPHardwareDataType 2>/dev/null \
        | awk -F': ' '/Chip:/{gsub(/^[ \t]+/,"",$2); print $2}')
    IS_APPLE_SILICON=true
elif echo "$cpu_brand" | grep -qi "apple"; then
    IS_APPLE_SILICON=true
else
    IS_APPLE_SILICON=false
fi

info "Model:   ${BOLD}$hw_model${RESET}"
info "Chip:    ${BOLD}$cpu_brand${RESET} ($cpu_cores cores)"
[ "$IS_APPLE_SILICON" = "true" ] && info "Arch:    ${BOLD}Apple Silicon (ARM64)${RESET}"
info "RAM:     ${BOLD}${total_ram_gb} GB${RESET}"
info "macOS:   ${BOLD}$os_version${RESET}"
info "Uptime:  ${BOLD}$uptime_str${RESET}"

uptime_days=$(uptime | grep -oE '[0-9]+ day' | grep -oE '[0-9]+' || echo "0")
if   (( uptime_days > 14 )); then warn "Mac has been running ${uptime_days} days without restart. Restart can free leaked memory."
elif (( uptime_days > 7  )); then warn "Uptime is ${uptime_days} days. Consider restarting if things feel sluggish."
else                               ok   "Uptime is reasonable ($uptime_days days)."
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 2. PENDING SYSTEM UPDATES
# ════════════════════════════════════════════════════════════════════════════
separator "2. PENDING SYSTEM UPDATES"
_html_section_open 2 "Pending System Updates"
info "Checking Apple servers for pending updates..."

updates_raw=$(softwareupdate -l 2>&1 || echo "")
if echo "$updates_raw" | grep -q "No new software available"; then
    ok "macOS is up to date."
else
    update_count=$(echo "$updates_raw" | grep -c "^\*" || echo "0")
    if (( update_count > 0 )); then
        warn "$update_count software update(s) pending. Background installd tasks may be consuming resources."
        echo "$updates_raw" | grep "^\*" | head -5 | while IFS= read -r line; do
            info "  ${line## }"
        done
        add_fix "Install pending updates ($update_count)|sudo softwareupdate -ia --verbose"
    else
        info "Software Update responded but output was unexpected. Check System Settings → General → Software Update."
    fi
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 3. AI TOOLS & AGENTS
# ════════════════════════════════════════════════════════════════════════════
separator "3. AI TOOLS & AGENTS"
_html_section_open 3 "AI Tools & Agents"

ai_anything_found=false

# ── Detect running AI processes & aggregate resource usage ────────────────
_ai_tools=(
    "Claude Desktop|/Applications/Claude.app"
    "Claude Code|claude.*--output-format\|claude.*--permission-prompt"
    "Ollama|/Applications/Ollama.app\|ollama serve"
    "LM Studio|/Applications/LM Studio.app\|\.lmstudio"
    "Cursor|/Applications/Cursor.app"
    "GitHub Copilot|copilot"
    "ChatGPT|com.openai.chat\|/Applications/ChatGPT.app"
    "Windsurf|/Applications/Windsurf.app"
    "Continue.dev|continue.*server"
)

# Collect all running AI tool data first (name|ram|cpu|cnt), sorted by RAM later
_ai_running_data=""
ai_total_ram=0
ai_total_cpu_str="0"
ai_total_procs=0

for _entry in "${_ai_tools[@]}"; do
    _name="${_entry%%|*}"
    _pattern="${_entry##*|}"

    _stats=$(ps aux | awk -v pat="$_pattern" '
    NR==1 {next}
    {
        cmd=""
        for(i=11;i<=NF;i++) cmd=cmd" "$i
        if (cmd ~ pat && cmd !~ /awk/ && cmd !~ /grep/) {
            cnt++; ram+=$6/1024; cpu+=$3
        }
    }
    END { if (cnt+0>0) printf "%d|%.0f|%.1f", cnt, ram, cpu }')

    [ -z "$_stats" ] && continue

    ai_anything_found=true
    _cnt="${_stats%%|*}";  _rest="${_stats#*|}"
    _ram="${_rest%%|*}";   _cpu="${_rest##*|}"

    ai_total_ram=$(( ai_total_ram + _ram ))
    ai_total_procs=$(( ai_total_procs + _cnt ))
    _ai_running_data="${_ai_running_data}${_name}|${_ram}|${_cpu}|${_cnt}"$'\n'
done

# ── Running AI Tools (sorted by RAM, descending) ────────────────────────
echo ""
echo -e "  ${BOLD}RUNNING AI TOOLS${RESET}"
echo -e "  ${DIM}┌──────────────────────────────────────────────────────────┐${RESET}"

if [ "$ai_anything_found" = "true" ]; then
    printf "  ${DIM}│${RESET} %-22s %8s  %6s  %5s ${DIM}│${RESET}\n" "Tool" "RAM" "CPU%" "Procs"
    echo -e "  ${DIM}├──────────────────────────────────────────────────────────┤${RESET}"

    echo -n "$_ai_running_data" | sort -t'|' -k2 -rn | while IFS='|' read -r _name _ram _cpu _cnt; do
        [ -z "$_name" ] && continue
        # Build a mini bar for RAM (max 10 chars, scaled to 2000MB)
        _bar_len=$(( _ram * 10 / 2000 ))
        (( _bar_len > 10 )) && _bar_len=10
        (( _bar_len < 1 && _ram > 0 )) && _bar_len=1
        _bar=""
        _i=0; while (( _i < _bar_len )); do _bar="${_bar}█"; _i=$((_i+1)); done
        while (( _i < 10 )); do _bar="${_bar}░"; _i=$((_i+1)); done

        if   (( _ram > 1000 )); then
            printf "  ${DIM}│${RESET} ${RED}▸ %-20s${RESET} %5d MB  %5.1f%%  %4d ${DIM}│${RESET}\n" "$_name" "$_ram" "$_cpu" "$_cnt"
            printf "  ${DIM}│${RESET}   ${RED}${_bar}${RESET}                                       ${DIM}│${RESET}\n"
        elif (( _ram > 300  )); then
            printf "  ${DIM}│${RESET} ${YELLOW}▸ %-20s${RESET} %5d MB  %5.1f%%  %4d ${DIM}│${RESET}\n" "$_name" "$_ram" "$_cpu" "$_cnt"
            printf "  ${DIM}│${RESET}   ${YELLOW}${_bar}${RESET}                                       ${DIM}│${RESET}\n"
        else
            printf "  ${DIM}│${RESET}   %-20s %5d MB  %5.1f%%  %4d ${DIM}│${RESET}\n" "$_name" "$_ram" "$_cpu" "$_cnt"
        fi
    done

    echo -e "  ${DIM}├──────────────────────────────────────────────────────────┤${RESET}"
    printf "  ${DIM}│${RESET} ${BOLD}%-22s %5d MB          %4d${RESET} ${DIM}│${RESET}\n" "TOTAL" "$ai_total_ram" "$ai_total_procs"
    echo -e "  ${DIM}└──────────────────────────────────────────────────────────┘${RESET}"
    echo ""
    if   (( ai_total_ram > 4000 )); then issue "AI tools consuming ${ai_total_ram}MB RAM! Significant resource usage."
    elif (( ai_total_ram > 2000 )); then warn  "AI tools using ${ai_total_ram}MB RAM."
    elif (( ai_total_ram > 0    )); then ok    "AI tool memory footprint is reasonable (${ai_total_ram}MB)."
    fi
else
    echo -e "  ${DIM}│${RESET}   No AI tools currently running.                         ${DIM}│${RESET}"
    echo -e "  ${DIM}└──────────────────────────────────────────────────────────┘${RESET}"
fi

# ── Local Model Storage ──────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}LOCAL MODEL STORAGE${RESET}"
echo -e "  ${DIM}┌──────────────────────────────────────────────────────────┐${RESET}"

ai_model_disk=0
_model_lines=""

# Ollama models
if [ -d "$HOME/.ollama/models" ]; then
    ollama_size=$(du -sh "$HOME/.ollama/models" 2>/dev/null | awk '{print $1}')
    ollama_kb=$(du -s "$HOME/.ollama/models" 2>/dev/null | awk '{print $1}' || echo "0")
    ai_model_disk=$(( ai_model_disk + ollama_kb ))
    ollama_model_count=$(ls "$HOME/.ollama/models/manifests/registry.ollama.ai/library/" 2>/dev/null | wc -l | tr -d ' ')
    ollama_model_list=$(ls "$HOME/.ollama/models/manifests/registry.ollama.ai/library/" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    printf "  ${DIM}│${RESET}   %-20s  ${BOLD}%8s${RESET}  (%s models)          ${DIM}│${RESET}\n" "Ollama" "$ollama_size" "$ollama_model_count"
    [ -n "$ollama_model_list" ] && printf "  ${DIM}│     Models: %s│${RESET}\n" "$(printf '%-43s' "$ollama_model_list")"
fi

# LM Studio models
if [ -d "$HOME/.lmstudio/models" ]; then
    lms_size=$(du -sh "$HOME/.lmstudio" 2>/dev/null | awk '{print $1}')
    lms_kb=$(du -s "$HOME/.lmstudio" 2>/dev/null | awk '{print $1}' || echo "0")
    ai_model_disk=$(( ai_model_disk + lms_kb ))
    lms_count=$(find "$HOME/.lmstudio/models" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l | tr -d ' ')
    printf "  ${DIM}│${RESET}   %-20s  ${BOLD}%8s${RESET}  (%s models)          ${DIM}│${RESET}\n" "LM Studio" "$lms_size" "$lms_count"
fi

# Hugging Face cache
if [ -d "$HOME/.cache/huggingface" ]; then
    hf_size=$(du -sh "$HOME/.cache/huggingface" 2>/dev/null | awk '{print $1}')
    hf_kb=$(du -s "$HOME/.cache/huggingface" 2>/dev/null | awk '{print $1}' || echo "0")
    ai_model_disk=$(( ai_model_disk + hf_kb ))
    printf "  ${DIM}│${RESET}   %-20s  ${BOLD}%8s${RESET}                       ${DIM}│${RESET}\n" "HuggingFace cache" "$hf_size"
fi

# GPT4All models
if [ -d "$HOME/Library/Application Support/nomic.ai" ]; then
    gpt4all_size=$(du -sh "$HOME/Library/Application Support/nomic.ai" 2>/dev/null | awk '{print $1}')
    gpt4all_kb=$(du -s "$HOME/Library/Application Support/nomic.ai" 2>/dev/null | awk '{print $1}' || echo "0")
    ai_model_disk=$(( ai_model_disk + gpt4all_kb ))
    printf "  ${DIM}│${RESET}   %-20s  ${BOLD}%8s${RESET}                       ${DIM}│${RESET}\n" "GPT4All" "$gpt4all_size"
fi

ai_model_disk_gb=$(( ai_model_disk / 1048576 ))
if (( ai_model_disk > 0 )); then
    echo -e "  ${DIM}├──────────────────────────────────────────────────────────┤${RESET}"
    printf "  ${DIM}│${RESET} ${BOLD}%-22s %8s${RESET}                       ${DIM}│${RESET}\n" "TOTAL" "${ai_model_disk_gb}GB"
    echo -e "  ${DIM}└──────────────────────────────────────────────────────────┘${RESET}"
    echo ""
    # Disk bar for model storage
    _mdisk_bar_len=$(( ai_model_disk_gb * 20 / 200 ))
    (( _mdisk_bar_len > 20 )) && _mdisk_bar_len=20
    (( _mdisk_bar_len < 1 )) && _mdisk_bar_len=1
    _mdisk_bar=""; _mi=0
    while (( _mi < _mdisk_bar_len )); do _mdisk_bar="${_mdisk_bar}█"; _mi=$((_mi+1)); done
    while (( _mi < 20 )); do _mdisk_bar="${_mdisk_bar}░"; _mi=$((_mi+1)); done
    if   (( ai_model_disk_gb > 100 )); then
        echo -e "  ${RED}${_mdisk_bar}${RESET}  ${ai_model_disk_gb}GB"
        warn "AI models using ${ai_model_disk_gb}GB disk — consider removing unused models."
    elif (( ai_model_disk_gb > 50 )); then
        echo -e "  ${YELLOW}${_mdisk_bar}${RESET}  ${ai_model_disk_gb}GB"
        warn "AI models using ${ai_model_disk_gb}GB disk."
    elif (( ai_model_disk_gb > 0 )); then
        echo -e "  ${GREEN}${_mdisk_bar}${RESET}  ${ai_model_disk_gb}GB"
        ok "AI model disk usage: ~${ai_model_disk_gb}GB"
    else
        ok "AI model disk usage is minimal."
    fi
else
    echo -e "  ${DIM}│${RESET}   No local AI models found.                              ${DIM}│${RESET}"
    echo -e "  ${DIM}└──────────────────────────────────────────────────────────┘${RESET}"
fi

# ── AI Tool Data & Usage ────────────────────────────────────────────────
_ai_data_found=false
_ai_data_lines=""

# Claude Code data dir
claude_dir_size=""
claude_dir_kb=0
if [ -d "$HOME/.claude" ]; then
    claude_dir_size=$(du -sh "$HOME/.claude" 2>/dev/null | awk '{print $1}')
    claude_dir_kb=$(du -s "$HOME/.claude" 2>/dev/null | awk '{print $1}' || echo "0")
    _ai_data_found=true
fi

# Claude Desktop data
claude_desk_size=""
claude_desk_kb=0
claude_desktop_dir="$HOME/Library/Application Support/Claude"
if [ -d "$claude_desktop_dir" ]; then
    claude_desk_size=$(du -sh "$claude_desktop_dir" 2>/dev/null | awk '{print $1}')
    claude_desk_kb=$(du -s "$claude_desktop_dir" 2>/dev/null | awk '{print $1}' || echo "0")
    _ai_data_found=true
fi

# Cursor AI data
cursor_total_mb=0
if [ -d "$HOME/.cursor" ] || [ -d "$HOME/Library/Application Support/Cursor" ]; then
    cursor_size_1=$(du -s "$HOME/.cursor" 2>/dev/null | awk '{print $1}' || echo "0")
    cursor_size_2=$(du -s "$HOME/Library/Application Support/Cursor" 2>/dev/null | awk '{print $1}' || echo "0")
    cursor_total_kb=$(( cursor_size_1 + cursor_size_2 ))
    cursor_total_mb=$(( cursor_total_kb / 1024 ))
    _ai_data_found=true
fi

if [ "$_ai_data_found" = "true" ]; then
    echo ""
    echo -e "  ${BOLD}AI TOOL DATA${RESET}"
    echo -e "  ${DIM}┌──────────────────────────────────────────────────────────┐${RESET}"
    [ -n "$claude_dir_size"  ] && printf "  ${DIM}│${RESET}   %-20s  ${BOLD}%8s${RESET}   ~/.claude              ${DIM}│${RESET}\n" "Claude Code" "$claude_dir_size"
    [ -n "$claude_desk_size" ] && printf "  ${DIM}│${RESET}   %-20s  ${BOLD}%8s${RESET}   ~/Library/App Support  ${DIM}│${RESET}\n" "Claude Desktop" "$claude_desk_size"
    (( cursor_total_mb > 0 ))  && printf "  ${DIM}│${RESET}   %-20s  ${BOLD}%5dMB${RESET}   ~/.cursor + App Support${DIM}│${RESET}\n" "Cursor AI" "$cursor_total_mb"
    echo -e "  ${DIM}└──────────────────────────────────────────────────────────┘${RESET}"
fi

# ── Claude Code Usage Stats ──────────────────────────────────────────────
claude_stats_file="$HOME/.claude/stats-cache.json"
if [ -f "$claude_stats_file" ]; then
    cc_stats=$(python3 -c "
import json, sys
with open('$claude_stats_file') as f:
    data = json.load(f)
daily = data.get('dailyActivity', [])
total_msgs = sum(d.get('messageCount', 0) for d in daily)
total_sess = sum(d.get('sessionCount', 0) for d in daily)
total_tool = sum(d.get('toolCallCount', 0) for d in daily)
days = len(daily)
recent = daily[-7:] if len(daily) >= 7 else daily
recent_msgs = sum(d.get('messageCount', 0) for d in recent)
recent_sess = sum(d.get('sessionCount', 0) for d in recent)
recent_tool = sum(d.get('toolCallCount', 0) for d in recent)
first = daily[0]['date'] if daily else '?'
last  = daily[-1]['date'] if daily else '?'
avg_msgs = total_msgs // days if days > 0 else 0
print(f'{total_msgs}|{total_sess}|{total_tool}|{days}|{first}|{last}|{recent_msgs}|{recent_sess}|{recent_tool}|{avg_msgs}')
" 2>/dev/null || echo "")

    if [ -n "$cc_stats" ]; then
        IFS='|' read -r cc_msgs cc_sess cc_tools cc_days cc_first cc_last cc_rmsg cc_rsess cc_rtool cc_avg <<< "$cc_stats"

        echo ""
        echo -e "  ${BOLD}CLAUDE CODE ACTIVITY${RESET}"
        echo -e "  ${DIM}┌──────────────────────────────────────────────────────────┐${RESET}"
        printf "  ${DIM}│${RESET}   Messages:  ${BOLD}%-8s${RESET}  Sessions:  ${BOLD}%-6s${RESET}              ${DIM}│${RESET}\n" "$cc_msgs" "$cc_sess"
        printf "  ${DIM}│${RESET}   Tool calls: ${BOLD}%-7s${RESET}  Active days: ${BOLD}%-4s${RESET}            ${DIM}│${RESET}\n" "$cc_tools" "$cc_days"
        printf "  ${DIM}│${RESET}   Period:     ${BOLD}%s → %s${RESET}                  ${DIM}│${RESET}\n" "$cc_first" "$cc_last"
        printf "  ${DIM}│${RESET}   Avg msgs/day: ${BOLD}%-6s${RESET}                                ${DIM}│${RESET}\n" "$cc_avg"
        echo -e "  ${DIM}├──────────────────────────────────────────────────────────┤${RESET}"
        printf "  ${DIM}│${RESET}   Last 7 active days:                                  ${DIM}│${RESET}\n"
        printf "  ${DIM}│${RESET}     ${BOLD}%s${RESET} msgs   ${BOLD}%s${RESET} sessions   ${BOLD}%s${RESET} tool calls       ${DIM}│${RESET}\n" "$cc_rmsg" "$cc_rsess" "$cc_rtool"
        echo -e "  ${DIM}└──────────────────────────────────────────────────────────┘${RESET}"

        (( cc_avg > 500 )) && info "  Power user — averaging ${cc_avg} messages/active day."
    fi
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 4. CPU ANALYSIS
# ════════════════════════════════════════════════════════════════════════════
separator "4. CPU ANALYSIS"
_html_section_open 4 "CPU Analysis"

load_avg=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
load_int=${load_avg%%.*}
CURRENT_cpu_load="$load_int"

info "Load average (1 min): ${BOLD}$load_avg${RESET} (cores: $cpu_cores)"
show_drift "$load_int" "$SNAP_cpu_load" ""

if   (( load_int > cpu_cores * 2 )); then issue "CPU severely overloaded! Load ($load_avg) is >2× core count ($cpu_cores)."
elif (( load_int > cpu_cores     )); then warn  "CPU load ($load_avg) exceeds core count ($cpu_cores). Processes are queuing."
else                                       ok    "CPU load is within normal range."
fi

echo ""
info "Top CPU consumers:"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
ps aux | sort -t' ' -k3 -rn | head -10 | while read -r user pid cpu mem vsz rss tt stat started time command; do
    cpu_val=${cpu%%.*}
    if   (( cpu_val > 80 )); then echo -e "  ${RED}▸ ${cpu}% CPU${RESET}  PID:${pid}  ${BOLD}${command:0:50}${RESET}"
    elif (( cpu_val > 30 )); then echo -e "  ${YELLOW}▸ ${cpu}% CPU${RESET}  PID:${pid}  ${command:0:50}"
    elif (( cpu_val >  5 )); then echo -e "    ${cpu}% CPU  PID:${pid}  ${command:0:50}"
    fi
done

echo ""
runaway=$(ps aux | awk 'NR>1 && $3+0 > 100 && $11 != "kernel_task" {print $11, $3"%"}')
if [ -n "$runaway" ]; then
    issue "Runaway processes detected (>100% CPU):"
    echo "$runaway" | head -5 | while IFS= read -r line; do
        echo -e "    ${RED}▸ $line${RESET}"
    done
fi

# ── kernel_task Explanation ───────────────────────────────────────────────────
kt_cpu=$(ps aux | awk '/[k]ernel_task/ {sum+=$3} END {printf "%.0f", sum+0}')
if (( kt_cpu > 200 )); then
    echo ""
    issue "kernel_task using ${kt_cpu}% CPU — your Mac is thermally throttling"
    echo -e "  ${CYAN}  → kernel_task is NOT a runaway process. It is macOS's thermal${RESET}"
    echo -e "  ${CYAN}    throttle guard — it deliberately slows the CPU when overheating.${RESET}"
    echo -e "  ${CYAN}  → Fix: Move to a hard flat surface, check vents, reduce workload.${RESET}"
elif (( kt_cpu > 100 )); then
    echo ""
    warn "kernel_task using ${kt_cpu}% CPU — moderate thermal throttling detected"
    echo -e "  ${DIM}  → macOS is slowing your CPU due to heat. Try a cooler surface.${RESET}"
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 5. MEMORY ANALYSIS
# ════════════════════════════════════════════════════════════════════════════
separator "5. MEMORY ANALYSIS"
_html_section_open 5 "Memory Analysis"

vm_stat_output=$(vm_stat)
page_size=$(echo "$vm_stat_output" | head -1 | grep -oE '[0-9]+')

pages_free=$(echo       "$vm_stat_output" | awk '/Pages free/             {gsub(/\./,"",$3); print $3+0}')
pages_active=$(echo     "$vm_stat_output" | awk '/Pages active/           {gsub(/\./,"",$3); print $3+0}')
pages_inactive=$(echo   "$vm_stat_output" | awk '/Pages inactive/         {gsub(/\./,"",$3); print $3+0}')
pages_wired=$(echo      "$vm_stat_output" | awk '/Pages wired/            {gsub(/\./,"",$4); print $4+0}')
pages_compressed=$(echo "$vm_stat_output" | awk '/Pages stored in compressor/ {gsub(/\./,"",$5); print $5+0}')
pageouts=$(echo         "$vm_stat_output" | awk '/Pageouts/               {gsub(/\./,"",$2); print $2+0}')

free_mb=$(( (pages_free       * page_size) / 1048576 ))
active_mb=$(( (pages_active   * page_size) / 1048576 ))
inactive_mb=$(( (pages_inactive * page_size) / 1048576 ))
wired_mb=$(( (pages_wired     * page_size) / 1048576 ))
compressed_mb=$(( (pages_compressed * page_size) / 1048576 ))
used_mb=$(( active_mb + wired_mb + compressed_mb ))
total_mb=$(( total_ram_gb * 1024 ))

info "Memory Breakdown:"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
info "  Active:     ${BOLD}${active_mb} MB${RESET}   (apps currently using)"
info "  Wired:      ${BOLD}${wired_mb} MB${RESET}   (kernel/system, cannot be freed)"
info "  Compressed: ${BOLD}${compressed_mb} MB${RESET}   (squeezed to save space)"
info "  Inactive:   ${BOLD}${inactive_mb} MB${RESET}   (recently used, reclaimable)"
info "  Free:       ${BOLD}${free_mb} MB${RESET}"

echo ""
info "Overall memory pressure:"
[ $total_mb -gt 0 ] && bar_chart "$used_mb" "$total_mb"

mem_used_pct=0
if (( total_mb > 0 )); then
    mem_used_pct=$(( used_mb * 100 / total_mb ))
    CURRENT_mem_pct="$mem_used_pct"
    if   (( mem_used_pct > 90 )); then issue "Memory usage at ${mem_used_pct}%! Severe memory pressure."
    elif (( mem_used_pct > 75 )); then warn  "Memory usage: ${mem_used_pct}%. Getting high."
    else                               ok    "Memory usage: ${mem_used_pct}%"
    fi
    show_drift "$mem_used_pct" "$SNAP_mem_pct" "%"
fi

# Apple Silicon — kernel-level pressure via memory_pressure command
if [ "$IS_APPLE_SILICON" = "true" ]; then
    echo ""
    mem_pressure_out=$(memory_pressure 2>/dev/null || echo "")
    if [ -n "$mem_pressure_out" ]; then
        free_pct=$(echo "$mem_pressure_out" | awk '/free percentage/ {match($0,/[0-9]+%/); print substr($0,RSTART,RLENGTH-1)+0}')
        pressure_level=$(echo "$mem_pressure_out" | awk '/System memory pressure/ && /NORMAL|WARN|CRITICAL/ {
            if      ($0 ~ /CRITICAL/) print "CRITICAL"
            else if ($0 ~ /WARN/)     print "WARNING"
            else                      print "NORMAL"
        }')
        [ -z "$pressure_level" ] && pressure_level="NORMAL"
        [ -z "$free_pct"       ] && free_pct=0

        info "Apple Silicon kernel pressure: ${BOLD}${pressure_level}${RESET} (${free_pct}% free)"
        if   echo "$pressure_level" | grep -q "CRITICAL"; then issue "Kernel reports CRITICAL memory pressure. Performance severely impacted."
        elif echo "$pressure_level" | grep -q "WARN";     then warn  "Kernel reports WARNING memory pressure."
        fi
    fi
fi

# Swap
swap_usage=$(sysctl -n vm.swapusage 2>/dev/null || echo "")
if [ -n "$swap_usage" ]; then
    swap_used=$(echo "$swap_usage" | grep -oE 'used = [0-9.]+M' | grep -oE '[0-9.]+' || echo "0")
    swap_used_int=${swap_used%%.*}
    CURRENT_swap_mb="$swap_used_int"
    echo ""
    if   (( swap_used_int > 2000 )); then issue "Swap usage is ${swap_used}MB! Heavy swapping causes major slowdowns."
    elif (( swap_used_int >  500 )); then warn  "Swap usage is ${swap_used}MB. Some memory pressure."
    else                                  ok    "Swap usage is low (${swap_used}MB)."
    fi
    show_drift "$swap_used_int" "$SNAP_swap_mb" "MB"
fi

CURRENT_pageouts="$pageouts"
(( pageouts > 100000 )) && warn "High pageout count ($pageouts since last boot — memory has been under chronic pressure)."

echo ""
info "Top memory consumers:"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
ps aux | sort -k6 -rn | head -10 | while read -r user pid cpu mem vsz rss tt stat started time command; do
    rss_mb=$(( rss / 1024 ))
    if   (( rss_mb > 1000 )); then echo -e "  ${RED}▸ ${rss_mb} MB${RESET}  PID:${pid}  ${BOLD}${command:0:50}${RESET}"
    elif (( rss_mb >  300 )); then echo -e "  ${YELLOW}▸ ${rss_mb} MB${RESET}  PID:${pid}  ${command:0:50}"
    elif (( rss_mb >   50 )); then echo -e "    ${rss_mb} MB  PID:${pid}  ${command:0:50}"
    fi
done

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 6. DISK ANALYSIS
# ════════════════════════════════════════════════════════════════════════════
separator "6. DISK ANALYSIS"
_html_section_open 6 "Disk Analysis"

disk_info=$(df -H / | tail -1)
disk_total=$(echo "$disk_info" | awk '{print $2}')
disk_used=$(echo  "$disk_info" | awk '{print $3}')
disk_avail=$(echo "$disk_info" | awk '{print $4}')
disk_pct=$(echo   "$disk_info" | awk '{print $5}' | tr -d '%')
CURRENT_disk_pct="$disk_pct"

info "Boot disk: ${BOLD}${disk_used}${RESET} used of ${disk_total} (${disk_avail} free)"
bar_chart "$disk_pct" 100
show_drift "$disk_pct" "$SNAP_disk_pct" "%"

if   (( disk_pct > 95 )); then
    issue "Disk almost full (${disk_pct}%)! macOS needs 10-15% free for swap, caches, and updates."
    info  "  Tip: Check ~/Downloads, ~/.Trash, ~/Library/Caches"
elif (( disk_pct > 85 )); then warn "Disk usage is high (${disk_pct}%). Consider freeing space."
else                            ok   "Disk space is adequate."
fi

echo ""
info "Disk I/O (snapshot):"
iostat_out=$(iostat -c 2 -w 1 2>/dev/null | tail -1 || echo "")
[ -n "$iostat_out" ] && echo -e "  ${DIM}$iostat_out${RESET}"

echo ""
info "Space breakdown:"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
downloads_size=$(du -sh ~/Downloads 2>/dev/null | awk '{print $1}' || echo "N/A")
trash_size=$(du -sh ~/.Trash 2>/dev/null | awk '{print $1}' || echo "0B")
[ -z "$trash_size" ] && trash_size="0B"
caches_size=$(du -sh ~/Library/Caches 2>/dev/null | awk '{print $1}' || echo "N/A")
logs_size=$(du -sh ~/Library/Logs 2>/dev/null | awk '{print $1}' || echo "N/A")
photos_size=$(du -sh ~/Pictures/Photos\ Library.photoslibrary 2>/dev/null | awk '{print $1}' || echo "")
ios_backup_size=$(du -sh ~/Library/Application\ Support/MobileSync/Backup 2>/dev/null | awk '{print $1}' || echo "")

info "  ~/Downloads:          ${BOLD}$downloads_size${RESET}"
info "  ~/.Trash:             ${BOLD}$trash_size${RESET}"
info "  ~/Library/Caches:     ${BOLD}$caches_size${RESET}"
info "  ~/Library/Logs:       ${BOLD}$logs_size${RESET}"
[ -n "$photos_size"      ] && info "  Photos Library:       ${BOLD}$photos_size${RESET}"
[ -n "$ios_backup_size"  ] && info "  iOS Backups:          ${BOLD}$ios_backup_size${RESET}"

# Trash fix
trash_kb=$(du -s ~/.Trash 2>/dev/null | awk '{print $1}' || echo "0")
if (( trash_kb > 500000 )); then
    warn "Trash contains significant data ($trash_size). Emptying it will free space."
    add_fix "Empty Trash ($trash_size)|rm -rf ~/.Trash/* && echo 'Trash emptied.'"
fi

# iOS backups
if [ -n "$ios_backup_size" ]; then
    ios_kb=$(du -s ~/Library/Application\ Support/MobileSync/Backup 2>/dev/null | awk '{print $1}' || echo "0")
    (( ios_kb > 10000000 )) && warn "iOS backups are large ($ios_backup_size). Manage in Finder → device → Manage Backups."
fi

# Purgeable space
purgeable=$(diskutil info / 2>/dev/null | awk -F': ' '/Purgeable/{gsub(/^[ \t]+/,"",$2); print $2}' | xargs || echo "")
[ -n "$purgeable" ] && info "  Purgeable (auto-reclaimable): ${BOLD}$purgeable${RESET}"

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 7. THERMAL & POWER STATE
# ════════════════════════════════════════════════════════════════════════════
separator "7. THERMAL & POWER STATE"
_html_section_open 7 "Thermal & Power"

thermal=$(pmset -g therm 2>/dev/null || echo "")
if echo "$thermal" | grep -qi "speed limit"; then
    speed_limit=$(echo "$thermal" | grep -i "speed" | grep -oE '[0-9]+' | head -1)
    if [ -n "$speed_limit" ] && (( speed_limit < 100 )); then
        issue "CPU thermally throttled to ${speed_limit}%! Mac is overheating."
        info  "  Tip: Check fan vents, reduce workload, use a cooling pad."
    else
        ok "No thermal throttling detected."
    fi
else
    ok "No thermal throttling detected."
fi

battery_info=$(pmset -g batt 2>/dev/null || echo "")
if echo "$battery_info" | grep -q "Battery"; then
    batt_pct=$(echo "$battery_info"    | grep -oE '[0-9]+%' | head -1)
    batt_status=$(echo "$battery_info" | grep -oE '(charging|discharging|charged|finishing charge)' | head -1)
    info "Battery: ${BOLD}$batt_pct${RESET} ($batt_status)"

    batt_health=$(system_profiler SPPowerDataType 2>/dev/null \
        | awk -F': ' '/Condition:/{gsub(/^[ \t]+/,"",$2); print $2}' || echo "")
    if [ -n "$batt_health" ]; then
        if echo "$batt_health" | grep -qi "normal"; then ok   "Battery condition: $batt_health"
        else                                              warn "Battery condition: ${BOLD}$batt_health${RESET}. Degraded battery can cause CPU throttling."
        fi
    fi

    echo "$battery_info" | grep -qi "Low Power" && warn "Low Power Mode is ON — performance is intentionally reduced."
fi

echo "$battery_info" | grep -qi "discharging" && warn "Running on battery. macOS may reduce CPU performance to save power."

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 8. SLEEP BLOCKERS
# ════════════════════════════════════════════════════════════════════════════
separator "8. SLEEP BLOCKERS"
_html_section_open 8 "Sleep Blockers"

pmset_out=$(pmset -g assertions 2>/dev/null || echo "")

# Parse process-level assertion lines (format: "   pid 123(processname): ... AssertionType named: ...")
sleep_blockers=$(echo "$pmset_out" | awk '
/pid [0-9]+/ && /PreventUserIdleSystemSleep|PreventSystemSleep/ {
    # Skip powerd — it is always there when display is on
    if (index($0, "powerd") != 0) next
    if (match($0, /pid [0-9]+/))   pid   = substr($0, RSTART+4, RLENGTH-4)
    if (match($0, /\([^)]+\)/))    pname = substr($0, RSTART+1, RLENGTH-2)
    if (match($0, /"[^"]+"/) )     reason = substr($0, RSTART+1, RLENGTH-2)
    printf "%s|%s|%s\n", pid, pname, reason
}')

if [ -z "$sleep_blockers" ]; then
    ok "No rogue sleep blockers detected."
else
    warn "Process(es) are preventing your Mac from sleeping:"
    while IFS='|' read -r pid pname reason; do
        echo -e "    ${YELLOW}▸ ${BOLD}${pname}${RESET} (PID $pid) — \"$reason\""
        add_fix "Kill sleep blocker: $pname (PID $pid)|kill $pid && echo 'Killed $pname'"
    done <<< "$sleep_blockers"
    info "  Tip: Sleep blockers drain battery and generate heat even when screen is off."
fi

# Display sleep blockers (informational — not always a problem)
display_blockers=$(echo "$pmset_out" | awk '
/pid [0-9]+/ && /PreventUserIdleDisplaySleep/ {
    if (index($0, "powerd") != 0) next
    if (index($0, "com.apple") != 0) next
    if (match($0, /\([^)]+\)/)) pname = substr($0, RSTART+1, RLENGTH-2)
    print pname
}')
if [ -n "$display_blockers" ]; then
    info "Display sleep blockers (media apps, expected in some cases):"
    echo "$display_blockers" | head -3 | while IFS= read -r nm; do
        echo -e "    ▸ $nm"
    done
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 9. SECURITY AUDIT
# ════════════════════════════════════════════════════════════════════════════
separator "9. SECURITY AUDIT"
_html_section_open 9 "Security Audit"

# FileVault
fv_status=$(fdesetup status 2>/dev/null | awk '{print tolower($0)}')
if echo "$fv_status" | grep -q "filevault is on"; then
    ok "FileVault disk encryption: ENABLED"
else
    issue "FileVault is DISABLED — your data is unencrypted. Enable in System Settings → Privacy & Security."
    add_fix "Enable FileVault|sudo fdesetup enable"
fi

# Firewall
fw_status=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | awk '{print tolower($0)}')
if echo "$fw_status" | grep -q "enabled"; then
    ok "Application Firewall: ENABLED"
else
    warn "Firewall is DISABLED — consider enabling in System Settings → Network."
    add_fix "Enable Firewall|sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"
fi

# SIP
sip_status=$(csrutil status 2>/dev/null | awk '{print tolower($0)}')
if echo "$sip_status" | grep -q "enabled"; then
    ok "System Integrity Protection (SIP): ENABLED"
else
    warn "SIP is DISABLED — system is less protected against malware and driver corruption."
fi

# Gatekeeper
gk_status=$(spctl --status 2>/dev/null | awk '{print tolower($0)}')
if echo "$gk_status" | grep -q "enabled"; then
    ok "Gatekeeper: ENABLED"
else
    warn "Gatekeeper is DISABLED — unsigned apps can run without any verification."
    add_fix "Enable Gatekeeper|sudo spctl --master-enable && echo 'Gatekeeper enabled'"
fi

# XProtect version (informational)
xp_ver=$(system_profiler SPInstallHistoryDataType 2>/dev/null \
    | awk '/XProtect/{found=1} found && /Version:/{gsub(/^[ \t]+/,"",$0); print $2; exit}')
[ -n "$xp_ver" ] && info "XProtect version: ${BOLD}$xp_ver${RESET}"

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 10. BACKGROUND PROCESSES & LAUNCH AGENTS
# ════════════════════════════════════════════════════════════════════════════
separator "10. BACKGROUND PROCESSES & LAUNCH AGENTS"
_html_section_open 10 "Background Processes"

total_procs=$(ps aux | wc -l | tr -d ' ')
CURRENT_processes="$total_procs"

info "Total running processes: ${BOLD}$total_procs${RESET}"
show_drift "$total_procs" "$SNAP_processes" ""

if   (( total_procs > 500 )); then warn "Very high process count ($total_procs). Many things competing for resources."
elif (( total_procs > 300 )); then info "Process count is moderate ($total_procs)."
else                               ok   "Process count is normal ($total_procs)."
fi

echo ""
info "Login Items (apps that start at login):"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
login_items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "")
if [ -n "$login_items" ]; then
    echo "$login_items" | tr ',' '\n' | while IFS= read -r item; do
        item=$(echo "$item" | xargs)
        [ -n "$item" ] && echo -e "    ▸ $item"
    done
    item_count=$(echo "$login_items" | tr ',' '\n' | wc -l | tr -d ' ')
    if (( item_count > 8 )); then
        warn "You have $item_count login items. Each uses memory/CPU at startup and ongoing."
        info "  Tip: System Settings → General → Login Items to trim the list."
    fi
else
    info "  Could not retrieve login items (permission may be needed)."
fi

echo ""
info "User LaunchAgents (background services):"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
user_agents_dir="$HOME/Library/LaunchAgents"
agent_count=0
if [ -d "$user_agents_dir" ]; then
    agent_count=$(ls -1 "$user_agents_dir"/*.plist 2>/dev/null | wc -l | tr -d ' ')
    if (( agent_count > 0 )); then
        ls -1 "$user_agents_dir"/*.plist 2>/dev/null | while IFS= read -r plist; do
            echo -e "    ▸ $(basename "$plist" .plist)"
        done
        (( agent_count > 15 )) && warn "$agent_count launch agents. Many third-party apps install hidden background services."
    else
        ok "No user launch agents found."
    fi
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 11. ICLOUD SYNC STATUS
# ════════════════════════════════════════════════════════════════════════════
separator "11. ICLOUD SYNC STATUS"
_html_section_open 11 "iCloud Sync"

brctl_raw=$(brctl status 2>/dev/null || echo "")
if [ -z "$brctl_raw" ]; then
    info "iCloud status unavailable (brctl not responding)."
else
    # First line: "NN containers matching '*'"
    container_count=$(echo "$brctl_raw" | head -1 | awk '{print $1+0}')
    foreground_count=$(echo "$brctl_raw" | grep -c "foreground" || true)
    foreground_count=${foreground_count:-0}
    active_count=$(echo "$brctl_raw" | grep -cE "uploading|downloading" || true)
    active_count=${active_count:-0}

    info "iCloud containers registered: ${BOLD}$container_count${RESET}"

    if (( foreground_count > 0 )); then
        warn "$foreground_count container(s) in foreground sync state — may be causing disk I/O spikes."
    else
        ok "iCloud sync is idle."
    fi

    (( active_count > 0 )) && info "$active_count container(s) actively uploading or downloading."

    # Stalled check: look for containers that haven't synced in a very long time
    # brctl obfuscates bundle IDs, so we count lines with old dates (before last month)
    # Using a simple heuristic: last-sync more than 30 days old
    cur_year=$(date +%Y)
    cur_month=$(date +%m)
    # Threshold: anything older than last month is considered stale
    if (( cur_month > 1 )); then
        thresh_year=$cur_year
        thresh_month=$(( cur_month - 1 ))
    else
        thresh_year=$(( cur_year - 1 ))
        thresh_month=12
    fi
    old_sync=$(echo "$brctl_raw" | grep "last-sync" | awk -v ty="$thresh_year" -v tm="$thresh_month" '{
        match($0, /last-sync:[0-9]{4}-[0-9]{2}/)
        if (RSTART > 0) {
            year  = substr($0, RSTART+11, 4)+0
            month = substr($0, RSTART+16, 2)+0
            if (year < ty || (year == ty && month < tm)) cnt++
        }
    } END {print cnt+0}')
    (( old_sync > 3 )) && warn "$old_sync containers have not synced since before last month. iCloud may be stalled."
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 12. SPOTLIGHT INDEXING
# ════════════════════════════════════════════════════════════════════════════
separator "12. SPOTLIGHT INDEXING"
_html_section_open 12 "Spotlight"

mdutil_status=$(mdutil -s / 2>/dev/null || echo "")
if echo "$mdutil_status" | grep -qi "enabled"; then
    mds_cpu=$(ps aux | awk '/[m]ds_stores|[m]dworker/ {sum += $3} END {printf "%.0f", sum+0}')
    if   (( mds_cpu > 50 )); then
        issue "Spotlight is actively indexing at ${mds_cpu}% CPU!"
        info  "  Tip: Exclude large folders in System Settings → Spotlight."
        add_fix "Pause Spotlight indexing|sudo mdutil -d / && echo 'Paused. Re-enable: sudo mdutil -E /'"
    elif (( mds_cpu > 10 )); then warn "Spotlight indexing using ${mds_cpu}% CPU."
    else                          ok   "Spotlight is enabled but idle (${mds_cpu}% CPU)."
    fi
else
    info "Spotlight indexing is disabled."
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 13. NETWORK & WIFI DIAGNOSTICS
# ════════════════════════════════════════════════════════════════════════════
separator "13. NETWORK & WIFI DIAGNOSTICS"
_html_section_open 13 "Network & WiFi"

active_iface=$(route get default 2>/dev/null | awk '/interface:/{print $2}' || echo "")
if [ -n "$active_iface" ]; then
    info "Active interface: ${BOLD}$active_iface${RESET}"

    # DNS timing — use perl (built-in on macOS, millisecond precision)
    dns_start=$(perl -e 'use Time::HiRes qw(gettimeofday); my ($s,$us)=gettimeofday(); print $s*1000+int($us/1000),"\n";' 2>/dev/null || date +%s)
    nslookup apple.com >/dev/null 2>&1
    dns_end=$(perl -e 'use Time::HiRes qw(gettimeofday); my ($s,$us)=gettimeofday(); print $s*1000+int($us/1000),"\n";' 2>/dev/null || date +%s)
    dns_ms=$(( dns_end - dns_start ))

    if   (( dns_ms > 500 )); then warn "DNS resolution is slow (${dns_ms}ms). Consider switching to 1.1.1.1 or 8.8.8.8."
    elif (( dns_ms > 200 )); then warn "DNS resolution is moderate (${dns_ms}ms)."
    else                          ok   "DNS resolution is fast (${dns_ms}ms)."
    fi

    vpn_count=$(ifconfig 2>/dev/null | grep -c '^utun' || echo "0")
    (( vpn_count > 2 )) && info "VPN active ($vpn_count tunnel interfaces). VPNs can slow network and cause DNS issues."

    # WiFi diagnostics — system_profiler (airport binary removed in macOS 14+)
    if echo "$active_iface" | grep -qE '^en'; then
        echo ""
        info "WiFi details:"
        wifi_data=$(system_profiler SPAirPortDataType 2>/dev/null || echo "")
        if [ -n "$wifi_data" ]; then
            # Extract from "Current Network Information" block
            wifi_ssid=$(echo "$wifi_data" | awk '
                /Current Network Information:/ {in_cur=1; found=0; next}
                in_cur && found==0 && /^            [^ ]/ && /:$/ {
                    gsub(/^[ \t]+|:[ \t]*$/, "")
                    print; found=1
                }
                /^        [A-Z]/ && in_cur && found {in_cur=0}
            ' | head -1)

            wifi_rssi=$(echo "$wifi_data" | awk '
                /Signal \/ Noise:/ {
                    match($0, /-[0-9]+/)
                    print substr($0, RSTART, RLENGTH)+0; exit
                }')
            wifi_noise=$(echo "$wifi_data" | awk '
                /Signal \/ Noise:/ {
                    # second negative number
                    s=$0; n=0
                    while (match(s, /-[0-9]+/)) {
                        n++; val=substr(s,RSTART,RLENGTH)+0
                        if (n==2) {print val; exit}
                        s=substr(s,RSTART+RLENGTH)
                    }
                }')
            wifi_channel=$(echo "$wifi_data" | awk '/Channel:/{match($0,/[0-9]+/); print substr($0,RSTART,RLENGTH)+0; exit}')
            wifi_txrate=$(echo "$wifi_data" | awk '/Transmit Rate:/{match($0,/[0-9]+/); print substr($0,RSTART,RLENGTH)+0; exit}')

            [ -n "$wifi_ssid"   ] && info "  Network:  ${BOLD}$wifi_ssid${RESET}"
            [ -n "$wifi_channel" ] && info "  Channel:  ${BOLD}$wifi_channel${RESET}"
            [ -n "$wifi_txrate" ] && info "  TX Rate:  ${BOLD}${wifi_txrate} Mbps${RESET}"

            if [ -n "$wifi_rssi" ] && [ -n "$wifi_noise" ]; then
                wifi_snr=$(( wifi_rssi - wifi_noise ))
                info "  Signal:   ${BOLD}${wifi_rssi} dBm${RESET}  Noise: ${wifi_noise} dBm  SNR: ${wifi_snr} dB"

                if   (( wifi_rssi < -80 )); then issue "WiFi signal is very weak (${wifi_rssi} dBm). Move closer to router."
                elif (( wifi_rssi < -70 )); then warn  "WiFi signal is weak (${wifi_rssi} dBm). May cause packet loss."
                else                             ok    "WiFi signal is good (${wifi_rssi} dBm)."
                fi

                if   (( wifi_snr < 10 )); then issue "WiFi SNR is critically low (${wifi_snr} dB). High interference."
                elif (( wifi_snr < 20 )); then warn  "WiFi SNR is marginal (${wifi_snr} dB). Some interference."
                else                          ok    "WiFi SNR is good (${wifi_snr} dB)."
                fi
            fi
        fi
    fi
else
    warn "No active network connection detected."
fi

echo ""
info "Processes with most network connections:"
echo -e "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
lsof -i -n -P 2>/dev/null | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn | head -5 | while read -r count name; do
    if (( count > 50 )); then echo -e "  ${YELLOW}▸ ${count} connections: ${BOLD}${name}${RESET}"
    else                      echo -e "    ▸ ${count} connections: ${name}"
    fi
done

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 14. GPU & GRAPHICS
# ════════════════════════════════════════════════════════════════════════════
separator "14. GPU & GRAPHICS"
_html_section_open 14 "GPU & Graphics"

ws_cpu=$(ps aux | awk '/[W]indowServer/{print $3; exit}')
ws_mem=$(ps aux | awk '/[W]indowServer/{print $6; exit}')
ws_mem_mb=$(( ${ws_mem:-0} / 1024 ))

if [ -n "$ws_cpu" ]; then
    ws_cpu_int=${ws_cpu%%.*}
    if   (( ws_cpu_int > 30 )); then
        issue "WindowServer using ${ws_cpu}% CPU (${ws_mem_mb}MB RAM). UI rendering is strained."
        info  "  Tip: Reduce transparency — System Settings → Accessibility → Display."
    elif (( ws_cpu_int > 15 )); then warn "WindowServer using ${ws_cpu}% CPU. Moderate graphics load."
    else                             ok   "WindowServer graphics load is normal (${ws_cpu}% CPU)."
    fi
fi

open_apps=$(osascript -e 'tell application "System Events" to count processes whose background only is false' 2>/dev/null || echo "0")
info "Open GUI applications: ${BOLD}$open_apps${RESET}"
(( open_apps > 20 )) && warn "Many apps open ($open_apps). Each consumes memory and WindowServer overhead."

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 15. ELECTRON APP ANALYSIS
# ════════════════════════════════════════════════════════════════════════════
separator "15. ELECTRON & CHROMIUM APP ANALYSIS"
_html_section_open 15 "Electron App Analysis"

info "Grouping Electron/Chromium-based helper processes by app bundle..."
echo ""

# Single awk pass over ps aux.
# Groups processes that contain Helper/Renderer/GPU/Plugin in their command
# and live under /Applications/AppName.app/
# Outputs: zero-padded-RAM<TAB>CPU<TAB>count<TAB>AppName
# GRAND TOTAL line uses app="TOTAL"
electron_output=$(ps aux | awk '
NR == 1 { next }
{
    cmd = ""
    for (i = 11; i <= NF; i++) cmd = cmd " " $i

    # Only Electron-style sub-processes (not the main .app launcher)
    if (cmd !~ /Helper|Renderer|GPU|Plugin/) next

    # Extract parent app name from /Applications/AppName.app/
    if (match(cmd, /\/Applications\/[^\/]+\.app\//)) {
        seg = substr(cmd, RSTART + 14, RLENGTH - 19)  # strip /Applications/ and .app/
        app = seg
    } else {
        next
    }

    cpu = $3 + 0
    ram = $6 / 1024    # KB -> MB

    app_cpu[app] += cpu
    app_ram[app] += ram
    app_cnt[app] += 1
    grand_ram     += ram
    grand_cpu     += cpu
    grand_cnt     += 1
}
END {
    for (app in app_cnt) {
        printf "%07.0f\t%.1f\t%d\t%s\n",
               app_ram[app], app_cpu[app], app_cnt[app], app
    }
    printf "%07.0f\t%.1f\t%d\tTOTAL\n", grand_ram, grand_cpu, grand_cnt
}' | sort -rn)

if [ -z "$electron_output" ]; then
    ok "No Electron/Chromium-based apps detected running."
else
    printf "  %-32s %8s  %6s  %5s\n" "App" "RAM" "CPU%" "Procs"
    echo -e "  ${DIM}──────────────────────────────────────────────────────────${RESET}"

    grand_ram_total=0

    while IFS="	" read -r ram_pad cpu cnt app; do
        ram_int="${ram_pad%%.*}"
        # Strip leading zeros for comparison
        ram_cmp=$(echo "$ram_int" | sed 's/^0*//')
        ram_cmp=${ram_cmp:-0}

        if [ "$app" = "TOTAL" ]; then
            grand_ram_total=$ram_cmp
            grand_cpu_total="$cpu"
            grand_cnt_total="$cnt"
            continue
        fi

        if   (( ram_cmp > 1000 )); then
            printf "  ${RED}▸ %-30s${RESET}  %5d MB  %5.1f%%  %4d\n" "$app" "$ram_cmp" "$cpu" "$cnt"
        elif (( ram_cmp > 400  )); then
            printf "  ${YELLOW}▸ %-30s${RESET}  %5d MB  %5.1f%%  %4d\n" "$app" "$ram_cmp" "$cpu" "$cnt"
        else
            printf "    %-30s  %5d MB  %5.1f%%  %4d\n" "$app" "$ram_cmp" "$cpu" "$cnt"
        fi
    done << ELECTRONEOF
$electron_output
ELECTRONEOF

    echo -e "  ${DIM}──────────────────────────────────────────────────────────${RESET}"
    printf "  %-32s %5d MB  %5.1f%%  %4d\n" "GRAND TOTAL" \
        "$grand_ram_total" "${grand_cpu_total:-0}" "${grand_cnt_total:-0}"

    echo ""
    if   (( grand_ram_total > 4000 )); then issue "Electron apps consuming ${grand_ram_total}MB RAM total! This is severe."
    elif (( grand_ram_total > 2000 )); then warn  "Electron apps using ${grand_ram_total}MB RAM total."
    elif (( grand_ram_total > 0    )); then ok    "Electron app memory footprint is reasonable (${grand_ram_total}MB total)."
    fi
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 16. ROSETTA 2 (APPLE SILICON ONLY)
# ════════════════════════════════════════════════════════════════════════════
separator "16. ROSETTA 2 (x86 TRANSLATION)"
_html_section_open 16 "Rosetta 2"

if [ "$IS_APPLE_SILICON" = "true" ]; then
    oahd_pid=$(ps aux | awk '/\/usr\/libexec\/rosetta\/oahd/ && !/awk/ {print $2; exit}')
    if [ -n "$oahd_pid" ]; then
        oahd_cpu=$(ps aux | awk '/[o]ahd/{sum+=$3} END {printf "%.1f", sum+0}')
        ok "Rosetta 2 translation daemon is active (PID $oahd_pid, ${oahd_cpu}% CPU)"

        # Find x86_64 apps — lsappinfo shows "Arch=X86_64" on the same line as the process entry
        x86_apps=$(lsappinfo list 2>/dev/null | awk '
        /bundle path=/ {
            if (match($0, /"[^"]+\.app[^"]*"/)) {
                path = substr($0, RSTART+1, RLENGTH-2)
                if (match(path, /\/([^\/]+\.app)/)) {
                    curr_app = substr(path, RSTART+1, RLENGTH-1)
                } else curr_app = ""
            }
        }
        /Arch=X86_64/ { if (curr_app != "") print curr_app }
        ' | sort -u)

        x86_count=0
        [ -n "$x86_apps" ] && x86_count=$(echo "$x86_apps" | wc -l | tr -d ' ')
        if (( x86_count > 0 )); then
            warn "$x86_count app(s) running under Rosetta 2 (x86 emulation adds ~15-30% overhead):"
            echo "$x86_apps" | head -10 | while IFS= read -r app; do
                echo -e "    ${YELLOW}▸ $app${RESET}  — check for an Apple Silicon native version"
            done
        else
            ok "Rosetta is active but no x86_64 apps detected currently running."
        fi
    else
        ok "Rosetta 2 daemon (oahd) is not running. All apps appear to be native ARM64."
    fi
else
    info "Rosetta 2 check skipped (Intel Mac)."
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 17. TIME MACHINE
# ════════════════════════════════════════════════════════════════════════════
separator "17. TIME MACHINE"
_html_section_open 17 "Time Machine"

tm_status=$(tmutil status 2>/dev/null || echo "")
if echo "$tm_status" | grep -q "Running = 1"; then
    issue "Time Machine backup is currently running! This uses significant disk I/O and CPU."
    backup_pct=$(echo "$tm_status" | grep "Percent" | grep -oE '[0-9.]+' || echo "?")
    info "  Backup progress: ${backup_pct}%"
    info "  Tip: sudo tmutil stopbackup to defer."
    add_fix "Stop current Time Machine backup|sudo tmutil stopbackup && echo 'Backup stopped.'"
else
    ok "Time Machine is not currently running."
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 18. KERNEL & SYSTEM HEALTH
# ════════════════════════════════════════════════════════════════════════════
separator "18. KERNEL & SYSTEM HEALTH"
_html_section_open 18 "Kernel & System Health"

panic_count=$(find /Library/Logs/DiagnosticReports -name "*.panic" -mtime -7 2>/dev/null | wc -l | tr -d ' ')
if (( panic_count > 0 )); then
    issue "$panic_count kernel panic(s) in the last 7 days! Indicates serious hardware or driver issues."
    info  "  Check: open /Library/Logs/DiagnosticReports"
else
    ok "No recent kernel panics (last 7 days)."
fi

crash_count=$(find ~/Library/Logs/DiagnosticReports -name "*.crash" -mtime -1 2>/dev/null | wc -l | tr -d ' ')
if   (( crash_count > 5 )); then warn "$crash_count app crashes in the last 24 hours. Check Console.app for details."
elif (( crash_count > 0 )); then info "$crash_count app crash(es) in the last 24 hours."
else                              ok   "No app crashes in the last 24 hours."
fi

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 19. DEVELOPER ENVIRONMENT
# ════════════════════════════════════════════════════════════════════════════
separator "19. DEVELOPER ENVIRONMENT"
_html_section_open 19 "Developer Environment"

dev_anything_found=false

# Node.js
node_info=$(ps aux | awk '
$11 ~ /\/node$/ || $11 ~ /nodemon/ || $11 ~ /ts-node/ || $11 ~ /\/node\/bin/ {
    if ($0 ~ /grep/) next
    cnt++; ram += $6/1024
}
END { if (cnt+0 > 0) printf "%d|%.0f\n", cnt, ram }')
if [ -n "$node_info" ]; then
    dev_anything_found=true
    node_cnt="${node_info%%|*}"
    node_ram="${node_info##*|}"
    info "Node.js: ${BOLD}$node_cnt process(es)${RESET}, ${BOLD}${node_ram}MB${RESET} RAM"
    (( node_cnt > 10 )) && warn "$node_cnt Node processes. Dev servers or watchers may be stacking up."
fi

# JVM / Java
jvm_info=$(ps aux | awk '
$11 ~ /\/java$/ || $11 ~ /\/jvm/ {
    if ($0 ~ /grep/) next
    cnt++; ram += $6/1024
}
END { if (cnt+0 > 0) printf "%d|%.0f\n", cnt, ram }')
if [ -n "$jvm_info" ]; then
    dev_anything_found=true
    jvm_cnt="${jvm_info%%|*}"
    jvm_ram="${jvm_info##*|}"
    info "JVM/Java: ${BOLD}$jvm_cnt process(es)${RESET}, ${BOLD}${jvm_ram}MB${RESET} RAM"
    (( jvm_ram > 2000 )) && warn "JVM processes using ${jvm_ram}MB. Review -Xmx heap settings."
fi

# Docker
docker_vm_ram=$(ps aux | awk '
/[Dd]ocker|[Hh]yperkit|[Vv]pnkit/ { ram += $6/1024 }
END { printf "%.0f", ram+0 }')
if (( docker_vm_ram > 0 )); then
    dev_anything_found=true
    docker_containers=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ' || echo "?")
    info "Docker: ${BOLD}${docker_vm_ram}MB${RESET} RAM, ${BOLD}${docker_containers}${RESET} running container(s)"
    (( docker_vm_ram > 2000 )) && warn "Docker VM using ${docker_vm_ram}MB. Stop unused containers."
elif [ -d "$HOME/Library/Containers/com.docker.docker" ]; then
    docker_disk=$(du -sh "$HOME/Library/Containers/com.docker.docker" 2>/dev/null | awk '{print $1}')
    [ -n "$docker_disk" ] && info "Docker data directory: ${BOLD}$docker_disk${RESET} (Docker Desktop not running)"
fi

# Xcode DerivedData
if [ -d ~/Library/Developer/Xcode/DerivedData ]; then
    dev_anything_found=true
    derived_size=$(du -sh ~/Library/Developer/Xcode/DerivedData 2>/dev/null | awk '{print $1}')
    derived_kb=$(du -s ~/Library/Developer/Xcode/DerivedData 2>/dev/null | awk '{print $1}' || echo "0")
    info "Xcode DerivedData: ${BOLD}$derived_size${RESET}"
    if (( derived_kb > 5000000 )); then
        warn "DerivedData is large (>5GB). Safe to delete when not actively building."
        add_fix "Clear Xcode DerivedData ($derived_size)|rm -rf ~/Library/Developer/Xcode/DerivedData && echo 'DerivedData cleared.'"
    fi
fi

# Homebrew cache
if [ -d ~/Library/Caches/Homebrew ]; then
    dev_anything_found=true
    brew_size=$(du -sh ~/Library/Caches/Homebrew 2>/dev/null | awk '{print $1}')
    brew_kb=$(du -s ~/Library/Caches/Homebrew 2>/dev/null | awk '{print $1}' || echo "0")
    info "Homebrew cache: ${BOLD}$brew_size${RESET}"
    if (( brew_kb > 2000000 )); then
        warn "Homebrew cache is large (>2GB)."
        add_fix "Clean Homebrew cache ($brew_size)|brew cleanup --prune=all && echo 'Homebrew cache cleaned.'"
    fi
fi

# Git FSEvents watchers (current user's open .git handles)
git_watchers=$(lsof -u "$(whoami)" 2>/dev/null | grep -c '\.git' || echo "0")
info "Open .git file handles (FSEvents watchers): ${BOLD}$git_watchers${RESET}"
if (( git_watchers > 100 )); then
    dev_anything_found=true
    warn "$git_watchers open .git handles. Many repos being watched simultaneously (jest, webpack, nodemon)."
fi

$dev_anything_found || info "No notable developer toolchain overhead detected."

_html_section_close

# ════════════════════════════════════════════════════════════════════════════
# 20. STORAGE OPTIMIZATION
# ════════════════════════════════════════════════════════════════════════════
separator "20. STORAGE OPTIMIZATION"
_html_section_open 20 "Storage Optimization"

# Xcode DerivedData already shown in section 18, skip here if large
# Docker disk (if not already shown in 18)
docker_disk=$(du -sh ~/Library/Containers/com.docker.docker 2>/dev/null | awk '{print $1}' || echo "")
[ -n "$docker_disk" ] && info "Docker image store: ${BOLD}$docker_disk${RESET}"

# Homebrew (if not dev environment)
brew_cache_storage=$(du -sh ~/Library/Caches/Homebrew 2>/dev/null | awk '{print $1}' || echo "N/A")
[ "$brew_cache_storage" != "N/A" ] && info "Homebrew cache: ${BOLD}$brew_cache_storage${RESET}"

# Mail
mail_size=$(du -sh ~/Library/Mail 2>/dev/null | awk '{print $1}' || echo "")
[ -n "$mail_size" ] && info "Mail data: ${BOLD}$mail_size${RESET}"

# Simulator runtimes (Xcode simulators can be huge)
sim_size=$(du -sh ~/Library/Developer/CoreSimulator 2>/dev/null | awk '{print $1}' || echo "")
if [ -n "$sim_size" ]; then
    info "iOS/macOS Simulators: ${BOLD}$sim_size${RESET}"
    sim_kb=$(du -s ~/Library/Developer/CoreSimulator 2>/dev/null | awk '{print $1}' || echo "0")
    if (( sim_kb > 20000000 )); then
        warn "Simulator runtimes are large (${sim_size}). Remove unused ones in Xcode → Settings → Platforms."
    fi
fi

# Application Support
appsupp_size=$(du -sh ~/Library/Application\ Support 2>/dev/null | awk '{print $1}' || echo "N/A")
[ "$appsupp_size" != "N/A" ] && info "~/Library/Application Support: ${BOLD}$appsupp_size${RESET}"

_html_section_close


# ════════════════════════════════════════════════════════════════════════════
# 21. CHANGES SINCE LAST RUN
# ════════════════════════════════════════════════════════════════════════════
if [ "$SNAP_LOADED" = "true" ]; then
    separator "21. CHANGES SINCE LAST RUN"
    _html_section_open 21 "Changes Since Last Run"

    snap_age=$(( $(date +%s) - SNAP_TIMESTAMP ))
    snap_h=$(( snap_age / 3600 ))
    snap_m=$(( (snap_age % 3600) / 60 ))
    info "Comparing to snapshot taken ${snap_h}h ${snap_m}m ago"
    echo ""

    # Issues
    issue_delta=$(( ISSUES_FOUND - SNAP_issues ))
    if   (( issue_delta > 0 )); then warn "Critical issues: $ISSUES_FOUND (was $SNAP_issues, +$issue_delta new)"
    elif (( issue_delta < 0 )); then ok   "Critical issues: $ISSUES_FOUND (was $SNAP_issues, ${issue_delta} resolved)"
    else                              ok   "Critical issues: $ISSUES_FOUND (unchanged)"
    fi

    # Warnings
    warn_delta=$(( WARNINGS_FOUND - SNAP_warnings ))
    if   (( warn_delta > 0 )); then warn "Warnings: $WARNINGS_FOUND (was $SNAP_warnings, +$warn_delta new)"
    elif (( warn_delta < 0 )); then ok   "Warnings: $WARNINGS_FOUND (was $SNAP_warnings, ${warn_delta} fewer)"
    else                            ok   "Warnings: $WARNINGS_FOUND (unchanged)"
    fi

    # Memory
    mem_delta=$(( CURRENT_mem_pct - SNAP_mem_pct ))
    if        (( mem_delta >  10 )); then warn "Memory usage: ${CURRENT_mem_pct}% (was ${SNAP_mem_pct}%, +${mem_delta}% higher)"
    elif      (( mem_delta < -10 )); then ok   "Memory usage: ${CURRENT_mem_pct}% (was ${SNAP_mem_pct}%, freed ${mem_delta#-}%)"
    else                                   info "Memory usage: ${CURRENT_mem_pct}% (stable, was ${SNAP_mem_pct}%)"
    fi

    # Swap
    swap_delta=$(( CURRENT_swap_mb - SNAP_swap_mb ))
    if   (( swap_delta >  500 )); then warn "Swap increased by ${swap_delta}MB since last run"
    elif (( swap_delta < -500 )); then ok   "Swap decreased by ${swap_delta#-}MB since last run"
    fi

    # Disk
    disk_delta=$(( CURRENT_disk_pct - SNAP_disk_pct ))
    if   (( disk_delta >  5 )); then warn "Disk usage grew by ${disk_delta}% since last run"
    elif (( disk_delta < -5 )); then ok   "Disk usage shrank by ${disk_delta#-}% since last run"
    fi

    # Processes
    proc_delta=$(( CURRENT_processes - SNAP_processes ))
    if   (( proc_delta > 50 )); then warn "Process count grew by $proc_delta since last run ($CURRENT_processes total)"
    elif (( proc_delta < -50 )); then ok  "Process count dropped by ${proc_delta#-} since last run ($CURRENT_processes total)"
    fi

    _html_section_close
fi

# ════════════════════════════════════════════════════════════════════════════
# SAVE SNAPSHOT
# ════════════════════════════════════════════════════════════════════════════
save_snapshot

# ════════════════════════════════════════════════════════════════════════════
# FINAL REPORT
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  DIAGNOSIS SUMMARY${RESET}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# ── Health Score ──────────────────────────────────────────────────────────────
HEALTH_SCORE=$(( 100 - ISSUES_FOUND * 10 - WARNINGS_FOUND * 3 ))
[ $HEALTH_SCORE -lt 0 ] && HEALTH_SCORE=0

if   (( HEALTH_SCORE >= 80 )); then SCORE_COLOR="${GREEN}";  SCORE_BADGE_CLASS="b-ok";   SCORE_LABEL="Healthy"
elif (( HEALTH_SCORE >= 60 )); then SCORE_COLOR="${YELLOW}"; SCORE_BADGE_CLASS="b-warn";  SCORE_LABEL="Fair"
elif (( HEALTH_SCORE >= 40 )); then SCORE_COLOR="${YELLOW}"; SCORE_BADGE_CLASS="b-warn";  SCORE_LABEL="Poor"
else                                 SCORE_COLOR="${RED}";    SCORE_BADGE_CLASS="b-crit";  SCORE_LABEL="Critical"
fi

score_filled=$(( HEALTH_SCORE * 30 / 100 ))
score_empty=$(( 30 - score_filled ))

echo -e "  ${BOLD}MAC HEALTH SCORE${RESET}"
printf "  ${SCORE_COLOR}${BOLD}"
printf '%0.s█' $(seq 1 $score_filled 2>/dev/null) || true
printf '%0.s░' $(seq 1 $score_empty  2>/dev/null) || true
printf "${RESET}  ${SCORE_COLOR}${BOLD}Health Score: %d / 100${RESET}  (%s)\n" "$HEALTH_SCORE" "$SCORE_LABEL"
echo ""
(( ISSUES_FOUND   > 0 )) && echo -e "  ${RED}    $ISSUES_FOUND critical issue(s)  × 10 pts = -$(( ISSUES_FOUND * 10 ))${RESET}"
(( WARNINGS_FOUND > 0 )) && echo -e "  ${YELLOW}    $WARNINGS_FOUND warning(s)       ×  3 pts = -$(( WARNINGS_FOUND * 3 ))${RESET}"
echo ""

# ── Ranked Vitals Dashboard ──────────────────────────────────────────────
echo -e "  ${BOLD}SYSTEM VITALS${RESET}  (ranked by severity)"
echo -e "  ${DIM}┌──────────────────────────────────────────────────────────┐${RESET}"

# Build vitals: name|value|max|unit|severity(0=ok,1=warn,2=crit)
_vitals=""

# Memory
_mem_sev=0
(( CURRENT_mem_pct > 75 )) && _mem_sev=1
(( CURRENT_mem_pct > 90 )) && _mem_sev=2
_mem_display=$CURRENT_mem_pct
(( _mem_display > 100 )) && _mem_display=100
_vitals="${_vitals}Memory|${_mem_display}|100|%|${_mem_sev}"$'\n'

# Disk
_disk_sev=0
(( CURRENT_disk_pct > 85 )) && _disk_sev=1
(( CURRENT_disk_pct > 95 )) && _disk_sev=2
_vitals="${_vitals}Disk|${CURRENT_disk_pct}|100|%|${_disk_sev}"$'\n'

# CPU Load
_cpu_sev=0
(( CURRENT_cpu_load > cpu_cores )) && _cpu_sev=1
(( CURRENT_cpu_load > cpu_cores * 2 )) && _cpu_sev=2
_cpu_load_pct=0
(( cpu_cores > 0 )) && _cpu_load_pct=$(( CURRENT_cpu_load * 100 / cpu_cores ))
(( _cpu_load_pct > 100 )) && _cpu_load_pct=100
_vitals="${_vitals}CPU Load|${_cpu_load_pct}|100|%|${_cpu_sev}"$'\n'

# Swap
_swap_sev=0
(( CURRENT_swap_mb > 500 )) && _swap_sev=1
(( CURRENT_swap_mb > 2000 )) && _swap_sev=2
_swap_pct=0
(( CURRENT_swap_mb > 0 )) && _swap_pct=$(( CURRENT_swap_mb * 100 / 4000 ))
(( _swap_pct > 100 )) && _swap_pct=100
_vitals="${_vitals}Swap|${_swap_pct}|100|MB (${CURRENT_swap_mb})|${_swap_sev}"$'\n'

# Processes
_proc_sev=0
(( CURRENT_processes > 300 )) && _proc_sev=1
(( CURRENT_processes > 500 )) && _proc_sev=2
_proc_pct=$(( CURRENT_processes * 100 / 600 ))
(( _proc_pct > 100 )) && _proc_pct=100
_vitals="${_vitals}Processes|${_proc_pct}|100| (${CURRENT_processes})|${_proc_sev}"$'\n'

# Sort vitals by severity (descending), then by value (descending)
echo -n "$_vitals" | sort -t'|' -k5 -rn -k2 -rn | while IFS='|' read -r _vname _vval _vmax _vunit _vsev; do
    [ -z "$_vname" ] && continue
    # Build mini bar (15 chars wide)
    _vbar_len=$(( _vval * 15 / _vmax ))
    (( _vbar_len > 15 )) && _vbar_len=15
    (( _vbar_len < 1 && _vval > 0 )) && _vbar_len=1
    _vbar=""; _vi=0
    while (( _vi < _vbar_len )); do _vbar="${_vbar}█"; _vi=$((_vi+1)); done
    while (( _vi < 15 )); do _vbar="${_vbar}░"; _vi=$((_vi+1)); done

    if   (( _vsev == 2 )); then _vc="${RED}";    _vicon="▸"
    elif (( _vsev == 1 )); then _vc="${YELLOW}"; _vicon="▸"
    else                        _vc="${GREEN}";  _vicon=" "
    fi

    echo -e "  ${DIM}│${RESET} ${_vicon} ${_vc}$(printf '%-12s' "$_vname") ${_vbar}${RESET}  $(printf '%3d' "$_vval")${_vunit}  ${DIM}│${RESET}"
done

echo -e "  ${DIM}└──────────────────────────────────────────────────────────┘${RESET}"
echo ""

if (( ISSUES_FOUND == 0 && WARNINGS_FOUND == 0 )); then
    echo -e "  ${GREEN}${BOLD}✓ Your Mac looks healthy!${RESET} No critical issues or warnings found."
    echo -e "  ${DIM}If it still feels slow, try a restart (uptime: $uptime_str).${RESET}"
else
    # ── Ranked Findings (most critical → least) ─────────────────────────
    echo -e "  ${BOLD}ALL FINDINGS${RESET}  (most → least critical)"
    echo -e "  ${DIM}┌──────────────────────────────────────────────────────────────────────┐${RESET}"

    _rank=1
    echo -n "$FINDINGS" | sort -t'|' -k1 -rn | while IFS='|' read -r _sev _sec _msg; do
        [ -z "$_msg" ] && continue
        # Truncate long messages
        _display_msg="$_msg"
        (( ${#_display_msg} > 58 )) && _display_msg="${_display_msg:0:55}..."

        if (( _sev == 2 )); then
            printf "  ${DIM}│${RESET} ${RED}${BOLD}%2d. [CRITICAL]${RESET} %-56s ${DIM}│${RESET}\n" "$_rank" "$_display_msg"
        else
            printf "  ${DIM}│${RESET} ${YELLOW}%2d. [WARNING]${RESET}  %-56s ${DIM}│${RESET}\n" "$_rank" "$_display_msg"
        fi
        _rank=$(( _rank + 1 ))
    done

    echo -e "  ${DIM}└──────────────────────────────────────────────────────────────────────┘${RESET}"
    echo ""

    echo -e "  ${BOLD}Quick wins:${RESET}"
    echo -e "    1. Restart your Mac — clears leaked memory and stale processes"
    echo -e "    2. Close apps you're not actively using (especially Electron apps)"
    echo -e "    3. Check Activity Monitor for runaway processes"
    echo -e "    4. Free disk space if below 15% free"
    echo -e "    5. Disable unused Login Items in System Settings"
    [ "$DO_FIX" = "false" ] && echo -e "    → Run with ${BOLD}--fix${RESET} to apply safe fixes interactively"
fi

echo ""
[ "$DO_SNAP" = "true" ] && echo -e "  ${DIM}Snapshot saved to: $SNAP_FILE${RESET}"
echo -e "  ${DIM}Report generated:  $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo -e "  ${DIM}Run again:         mac-doctor [--fix] [--html] [--no-snap]${RESET}"
echo ""
echo -e "  ${DIM}If Mac Doctor helped, consider supporting the project:${RESET}"
echo -e "  ${DIM}  ☕  buymeacoffee.com/crazymahii${RESET}"
echo -e "  ${DIM}  ♥   github.com/sponsors/mahii6991${RESET}"
echo ""

# ════════════════════════════════════════════════════════════════════════════
# INTERACTIVE FIX MODE
# ════════════════════════════════════════════════════════════════════════════
if [ "$DO_FIX" = "true" ] && (( FIX_COUNT > 0 )); then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}  INTERACTIVE FIX MODE${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo -e "  Found ${BOLD}$FIX_COUNT${RESET} fixable item(s):"
    echo ""

    i=0
    while [ $i -lt $FIX_COUNT ]; do
        label="${FIX_ACTIONS[$i]%%|*}"
        printf "  [%2d] %s\n" "$i" "$label"
        i=$(( i + 1 ))
    done

    echo ""
    printf "  Enter numbers to apply (space-separated), 'all' to apply all, or press Enter to skip: "
    read -r user_input < /dev/tty

    if [ -z "$user_input" ] || [ "$user_input" = "q" ] || [ "$user_input" = "n" ]; then
        echo -e "  ${DIM}Fix mode skipped.${RESET}"
    elif [ "$user_input" = "all" ]; then
        i=0
        while [ $i -lt $FIX_COUNT ]; do
            label="${FIX_ACTIONS[$i]%%|*}"
            cmd="${FIX_ACTIONS[$i]##*|}"
            echo ""
            echo -e "  ${CYAN}Applying: $label${RESET}"
            echo -e "  ${DIM}\$ $cmd${RESET}"
            eval "$cmd"
            ok "Done."
            i=$(( i + 1 ))
        done
    else
        for choice in $user_input; do
            if echo "$choice" | grep -qE '^[0-9]+$' && [ "$choice" -lt "$FIX_COUNT" ] 2>/dev/null; then
                label="${FIX_ACTIONS[$choice]%%|*}"
                cmd="${FIX_ACTIONS[$choice]##*|}"
                echo ""
                echo -e "  ${CYAN}Applying: $label${RESET}"
                echo -e "  ${DIM}\$ $cmd${RESET}"
                eval "$cmd"
                ok "Done."
            fi
        done
    fi
    echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# HTML REPORT EXPORT
# ════════════════════════════════════════════════════════════════════════════
[ "$DO_HTML" = "true" ] && generate_html_report
