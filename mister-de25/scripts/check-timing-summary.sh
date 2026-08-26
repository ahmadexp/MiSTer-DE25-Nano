#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: check-timing-summary.sh SUMMARY [TIMING_REPORT]" >&2
    exit 2
fi

summary=$1
report=${2:-${summary%.summary}.rpt}
if [[ ! -r $summary ]]; then
    echo "Timing summary is not readable: $summary" >&2
    exit 2
fi
if [[ ! -r $report ]]; then
    echo "Timing report is not readable: $report" >&2
    exit 2
fi

for analysis in setup hold; do
    if grep -Fq "Design is not fully constrained for $analysis requirements" \
            "$report"; then
        echo "Timing gate failed: design is not fully constrained for $analysis" >&2
        exit 1
    fi
    if ! grep -Fq "Design is fully constrained for $analysis requirements" \
            "$report"; then
        echo "Timing gate found no full-constraint verdict for $analysis" >&2
        exit 2
    fi
done

awk '
BEGIN {
    timing_type = "unknown timing check"
    checks = 0
    failures = 0
}
/^[[:space:]]*Type[[:space:]]*:/ {
    timing_type = $0
    sub(/^[[:space:]]*Type[[:space:]]*:[[:space:]]*/, "", timing_type)
    next
}
/^[[:space:]]*Slack[[:space:]]*:/ {
    slack_text = $0
    sub(/^[[:space:]]*Slack[[:space:]]*:[[:space:]]*/, "", slack_text)
    sub(/[[:space:]].*$/, "", slack_text)
    if (slack_text !~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$/) {
        printf "Timing gate found an invalid Slack value: %s\n", slack_text > "/dev/stderr"
        exit 2
    }
    slack = slack_text + 0
    checks++
    if (checks == 1 || slack < worst_slack) {
        worst_slack = slack
        worst_type = timing_type
    }
    if (slack < 0) {
        failures++
        failure_text = failure_text sprintf("  %+.3f ns  %s\n", slack, timing_type)
    }
}
END {
    if (checks == 0) {
        print "Timing gate found no Slack entries" > "/dev/stderr"
        exit 2
    }
    if (failures != 0) {
        printf "Timing gate failed: %d negative slack entries\n", failures > "/dev/stderr"
        printf "%s", failure_text > "/dev/stderr"
        exit 1
    }
    printf "Timing gate passed: %d checks, worst slack %+.3f ns (%s)\n", \
        checks, worst_slack, worst_type
}
' "$summary"
