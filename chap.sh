#!/usr/bin/env bash
# chap - Add chapters to an MP4 or MKV video using ffmpeg.
#
# Usage:
#   chap <input> ["MM:SS Title" ...] [-f chapters.txt] [-o output] [-w]
#
# Options:
#   -f <file>   Read chapters from a .txt file (one "TIMESTAMP Title" per line)
#   -o <path>   Set the output file path/name
#   -w          Overwrite the input file in place
#
# At least one chapter source (-f or inline args) is required.
# -o and -w are mutually exclusive.

set -euo pipefail

HELPER="/usr/local/lib/chap/helper.py"
SPEC="/usr/local/lib/chap/chap.usage.kdl"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

_tty_colors() { [[ -z "${NO_COLOR:-}" && -t 2 ]]; }

log_info() { _tty_colors && echo -e "\033[0;36m[INFO]\033[0m $*" >&2 || echo "[INFO] $*" >&2; }
log_ok()   { _tty_colors && echo -e "\033[0;32m[ OK ]\033[0m $*" >&2 || echo "[ OK ] $*" >&2; }
log_warn() { _tty_colors && echo -e "\033[0;33m[WARN]\033[0m $*" >&2 || echo "[WARN] $*" >&2; }
log_fail() { _tty_colors && echo -e "\033[1;31m[FAIL]\033[0m $*" >&2 || echo "[FAIL] $*" >&2; exit 1; }

die() { log_fail "$*"; }

# ---------------------------------------------------------------------------
# Usage spec (for shell completions via usage-cli)
# ---------------------------------------------------------------------------

usage() {
    cat >&2 <<EOF
Usage: chap <input_video> ["MM:SS Title" ...] [-f chapters.txt] [-o output] [-w]

Arguments:
  <input_video>       Path to the source MP4 or MKV file (required)
  "MM:SS Title"       One or more inline chapter definitions (optional)

Options:
  -f <file>           Read chapters from a .txt file
  -o <path>           Output file path/name (default: <name>_chap.<ext>)
  -w                  Overwrite the input file in place
  -h, --help          Show this help message

Notes:
  - At least one chapter source (-f or inline args) is required.
  - -o and -w are mutually exclusive.
  - When using -f and inline args together, file chapters come first.
  - Supported formats: MP4, MKV.

Chapter file format (.txt):
  # This is a comment
  00:00 Intro
  01:30 Main Content
  05:00 Outro
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

INPUT=""
CHAPTERS_FILE=""
OUTPUT=""
OVERWRITE=0
INLINE_CHAPTERS=()

if [[ $# -eq 0 ]]; then
    usage
fi

# --usage-spec: print the KDL spec for shell completion generation and exit
if [[ "${1:-}" == "--usage-spec" ]]; then
    if [[ -f "$SPEC" ]]; then
        cat "$SPEC"
    else
        # Fallback: emit the spec inline so completions work even before install
        cat <<'SPEC'
name chap
bin chap
about "Add chapters to MP4 and MKV videos — no re-encoding, no quality loss."

arg <input_video> help="Path to the source MP4 or MKV file"

arg "[CHAPTERS]…" help="Inline chapter definitions, e.g. \"00:00 Intro\" \"01:30 Main Content\"" required=#false var=#true

flag "-f --file" help="Read chapters from a .txt file (one 'TIMESTAMP Title' per line)" {
    arg <FILE>
}

flag "-o --output" help="Output file path/name (default: <name>_chap.<ext> in the same directory)" {
    arg <PATH>
}

flag "-w --overwrite" help="Overwrite the input file in place (mutually exclusive with -o)"

flag "-h --help" help="Print help"
SPEC
    fi
    exit 0
fi

# The first positional argument is the input file (unless it starts with -)
if [[ "${1:-}" != -* ]]; then
    INPUT="$1"
    shift
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f)
            [[ $# -lt 2 ]] && die "-f requires a file argument."
            CHAPTERS_FILE="$2"
            shift 2
            ;;
        -o)
            [[ $# -lt 2 ]] && die "-o requires a path argument."
            OUTPUT="$2"
            shift 2
            ;;
        -w)
            OVERWRITE=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            die "Unknown option: '$1'. Run 'chap --help' for usage."
            ;;
        *)
            INLINE_CHAPTERS+=("$1")
            shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

[[ -z "$INPUT" ]]  && die "No input file specified. Run 'chap --help' for usage."
[[ -f "$INPUT" ]]  || die "Input file not found: '$INPUT'"

EXT="${INPUT##*.}"
EXT_LOWER="${EXT,,}"
[[ "$EXT_LOWER" == "mp4" || "$EXT_LOWER" == "mkv" ]] || \
    die "Unsupported file format: '.$EXT'. Only MP4 and MKV are supported."

[[ -z "$CHAPTERS_FILE" && ${#INLINE_CHAPTERS[@]} -eq 0 ]] && \
    die "No chapters provided. Use -f <file> and/or inline 'MM:SS Title' arguments."

[[ $OVERWRITE -eq 1 && -n "$OUTPUT" ]] && \
    die "-o and -w are mutually exclusive. Use one or the other."

[[ -f "$HELPER" ]] || \
    die "helper.py not found at '$HELPER'. Please run setup.sh to install chap."

# ---------------------------------------------------------------------------
# Determine output path
# ---------------------------------------------------------------------------

if [[ $OVERWRITE -eq 1 ]]; then
    TMP_OUTPUT="$(mktemp --suffix=".${EXT_LOWER}" --tmpdir "chap_out_XXXXXX")"
    FINAL_OUTPUT="$INPUT"
elif [[ -n "$OUTPUT" ]]; then
    TMP_OUTPUT="$OUTPUT"
    FINAL_OUTPUT="$OUTPUT"
else
    DIR="$(dirname "$INPUT")"
    BASE="$(basename "$INPUT" ".$EXT")"
    TMP_OUTPUT="${DIR}/${BASE}_chap.${EXT_LOWER}"
    FINAL_OUTPUT="$TMP_OUTPUT"
fi

# ---------------------------------------------------------------------------
# Cleanup trap
# ---------------------------------------------------------------------------

META_FILE=""

cleanup() {
    [[ -n "$META_FILE" && -f "$META_FILE" ]] && rm -f "$META_FILE"
    if [[ $OVERWRITE -eq 1 && -f "${TMP_OUTPUT:-}" && "$TMP_OUTPUT" != "$FINAL_OUTPUT" ]]; then
        rm -f "$TMP_OUTPUT"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

HELPER_ARGS=()
[[ -n "$CHAPTERS_FILE" ]] && HELPER_ARGS+=("-f" "$CHAPTERS_FILE")
for chap in "${INLINE_CHAPTERS[@]}"; do
    HELPER_ARGS+=("$chap")
done

log_info "Generating chapter metadata..."
META_FILE="$(python3 "$HELPER" "${HELPER_ARGS[@]}")" || exit 1

log_info "Embedding chapters into video..."

ffmpeg \
    -loglevel error \
    -i "$INPUT" \
    -i "$META_FILE" \
    -map_metadata 1 \
    -map_chapters 1 \
    -codec copy \
    "$TMP_OUTPUT" \
    </dev/null

if [[ $OVERWRITE -eq 1 ]]; then
    mv "$TMP_OUTPUT" "$FINAL_OUTPUT"
fi

log_ok "Done: '$FINAL_OUTPUT'"
