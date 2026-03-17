#!/bin/zsh
set -euo pipefail
emulate -L zsh

if (( $# < 1 || $# > 2 )); then
  print -u2 "Usage: $0 /path/to/Codex.dmg.manifest.tsv [/path/to/output.dmg]"
  exit 1
fi

manifest=$1
[[ -f "$manifest" ]] || { print -u2 "Manifest not found: $manifest"; exit 1; }

chunk_dir=${manifest:h}
typeset original_name=""
typeset original_size=""
typeset original_sha256=""
typeset -a parts=()
typeset -A part_hashes

while IFS=$'\t' read -r kind col2 col3; do
  [[ -z "${kind:-}" ]] && continue
  [[ "$kind" == \#* ]] && continue

  case "$kind" in
    ORIGINAL_NAME)   original_name="$col2" ;;
    ORIGINAL_SIZE)   original_size="$col2" ;;
    ORIGINAL_SHA256) original_sha256="$col2" ;;
    PART)
      parts+=("$col2")
      part_hashes["$col2"]="$col3"
      ;;
  esac
done < "$manifest"

[[ -n "$original_name" ]]   || { print -u2 "Manifest missing ORIGINAL_NAME"; exit 1; }
[[ -n "$original_size" ]]   || { print -u2 "Manifest missing ORIGINAL_SIZE"; exit 1; }
[[ -n "$original_sha256" ]] || { print -u2 "Manifest missing ORIGINAL_SHA256"; exit 1; }
(( ${#parts[@]} > 0 ))      || { print -u2 "Manifest contains no PART entries"; exit 1; }

output=${2:-"$chunk_dir/$original_name"}
mkdir -p -- "${output:h}"

tmp="${output}.partial.$$"
trap 'rm -f -- "$tmp"' EXIT
: > "$tmp"

for part in "${parts[@]}"; do
  part_path="$chunk_dir/$part"
  [[ -f "$part_path" ]] || { print -u2 "Missing chunk: $part_path"; exit 1; }

  expected_part_hash="${part_hashes[$part]}"
  actual_part_hash=$(shasum -a 256 "$part_path" | awk '{print $1}')

  [[ "$actual_part_hash" == "$expected_part_hash" ]] || {
    print -u2 "SHA256 mismatch for chunk: $part"
    print -u2 "Expected: $expected_part_hash"
    print -u2 "Actual:   $actual_part_hash"
    exit 1
  }

  cat -- "$part_path" >> "$tmp"
done

actual_size=$(wc -c < "$tmp" | tr -d '[:space:]')
[[ "$actual_size" == "$original_size" ]] || {
  print -u2 "Output size mismatch"
  print -u2 "Expected: $original_size"
  print -u2 "Actual:   $actual_size"
  exit 1
}

actual_hash=$(shasum -a 256 "$tmp" | awk '{print $1}')
[[ "$actual_hash" == "$original_sha256" ]] || {
  print -u2 "Final SHA256 mismatch"
  print -u2 "Expected: $original_sha256"
  print -u2 "Actual:   $actual_hash"
  exit 1
}

mv -f -- "$tmp" "$output"
trap - EXIT

print "Reassembled: $output"
print "SHA256 verified: $actual_hash"
