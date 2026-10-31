#!/bin/bash
# Verify that every option in a config fragment survived the merge into .config.
#   scripts/check-config.sh <path/to/.config> <fragment>
# Exits non-zero if a required option is missing (usually an unmet Kconfig dependency).
set -euo pipefail
CONFIG="$1"; FRAG="$2"
fail=0
while IFS= read -r line; do
	case "$line" in
		CONFIG_*=*)
			opt="${line%%=*}"; want="${line#*=}"
			got="$(grep -E "^${opt}=" "$CONFIG" | head -1 | cut -d= -f2- || true)"
			if [ "$got" != "$want" ]; then
				printf '  MISSING  %-28s want %-10s got %s\n' "$opt" "$want" "${got:-<not set>}"
				fail=1
			fi ;;
		"# CONFIG_"*" is not set")
			opt="${line#\# }"; opt="${opt%% *}"
			if grep -qE "^${opt}=[ym]" "$CONFIG"; then
				printf '  STILL ON %s\n' "$opt"; fail=1
			fi ;;
	esac
done < "$FRAG"
if [ $fail = 0 ]; then echo "  config fragment OK ($(grep -c '^CONFIG_' "$FRAG") options)"; fi
exit $fail
