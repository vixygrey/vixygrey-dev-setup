#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INVENTORY="$ROOT/config/generated-outputs.tsv"
SCRIPT="$ROOT/scripts/setup-dev-tools-mac.sh"

[[ -s "$INVENTORY" ]] || { echo "generated-output inventory is missing" >&2; exit 1; }

awk -F'|' '
BEGIN {
    policies["managed"]; policies["managed-script"]; policies["generated"]
    policies["merged"]; policies["seed"]; policies["create-once"]; policies["superseded"]
    categories["configs"]; categories["always"]
    parsers["none"]; parsers["jq"]; parsers["taplo"]; parsers["yq"]
    parsers["plutil"]; parsers["bash"]; parsers["zellij"]; parsers["git"]
}
NR == 1 { next }
NF != 7 { printf "inventory row %d has %d fields, expected 7\n", NR, NF > "/dev/stderr"; bad=1; next }
$1 == "" || $2 == "" { printf "inventory row %d has an empty id or path\n", NR > "/dev/stderr"; bad=1 }
seen[$1]++ { printf "duplicate inventory id: %s\n", $1 > "/dev/stderr"; bad=1 }
!($3 in policies) { printf "unknown inventory policy: %s\n", $3 > "/dev/stderr"; bad=1 }
!($5 in categories) { printf "unknown inventory category: %s\n", $5 > "/dev/stderr"; bad=1 }
!($6 in parsers) { printf "unknown inventory parser: %s\n", $6 > "/dev/stderr"; bad=1 }
END { exit bad }
' "$INVENTORY"

declared="$(mktemp)"
inventoried="$(mktemp)"
trap 'rm -f "$declared" "$inventoried"' EXIT

perl -ne '
    while (/(write_managed_script|write_managed|write_generated|write_seed_once|merge_json_defaults|remove_superseded_managed)\s+"([^"]+)"/g) {
        %policy = (
            write_managed => "managed",
            write_managed_script => "managed-script",
            write_generated => "generated",
            write_seed_once => "seed",
            merge_json_defaults => "merged",
            remove_superseded_managed => "superseded"
        );
        print "$2|$policy{$1}\n";
    }
' "$SCRIPT" | sort -u > "$declared"
awk -F'|' 'NR > 1 {print $2 "|" $3}' "$INVENTORY" | sort -u > "$inventoried"

missing="$(comm -23 "$declared" "$inventoried")"
if [[ -n "$missing" ]]; then
    echo "generated outputs missing from the inventory:" >&2
    printf '%s\n' "$missing" >&2
    exit 1
fi

while IFS='|' read -r _id _path _policy _format _category _parser verifier; do
    [[ "$verifier" == "none" ]] && continue
    if ! grep -qF "|$verifier|" "$SCRIPT"; then
        echo "unknown runtime verifier label: $verifier" >&2
        exit 1
    fi
done < <(tail -n +2 "$INVENTORY")

printf 'generated-output inventory: %s entries valid\n' "$(( $(wc -l < "$INVENTORY") - 1 ))"
