#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the known-answer probe (built by mayhem/build.sh) against fixed inputs.
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

KAT="$SRC/mayhem/kat/target/release/vector-kat"
FX="$SRC/mayhem/kat/fixtures"
DNS="$SRC/mayhem/dnsmsg_parse/testsuite"
VRL="$SRC/mayhem/parse/testsuite"

passed=0
failed=0

# check <name> <expected> <mode> <file>: run the probe and compare its whole output to <expected>.
check() {
  local name="$1" expected="$2" mode="$3" file="$4" actual
  actual="$("$KAT" "$mode" "$file" 2>&1)" || actual="$actual [exit $?]"
  if [ "$actual" = "$expected" ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$name" "$expected" "$actual" >&2
  fi
}

if [ ! -x "$KAT" ]; then
  echo "probe missing at $KAT (mayhem/build.sh builds it)" >&2
  emit_ctrf "vector-kat" 0 1 0
  exit $?
fi

# dnsmsg-parser: packets from the crate's own unit tests, same expectations.
check dns-soa-query \
  $'qr=0 questions=1\nquestion=h5.example.com. type=SOA' dns "$DNS/soa_query.bin"
check dns-ede \
  $'qr=0 questions=1\nquestion=h5.example.com. type=SOA\nede=21 purpose=Not Supported extra=none' dns "$DNS/ede.bin"
check dns-ede-extra-text \
  $'qr=0 questions=1\nquestion=h5.example.com. type=SOA\nede=9 purpose=DNSKEY Missing extra=no SEP matching the DS found for dnssec-failed.org.' dns "$DNS/ede_text.bin"
check dns-garbage 'dns=error' dns "$FX/garbage.bin"

# VRL: parser, compiler and runtime.
check vrl-parse-ok 'parse=ok expressions=3' vrl-parse "$VRL/assign.vrl"
check vrl-parse-error 'parse=error' vrl-parse "$FX/lex_error.vrl"
check vrl-compile-error 'compile=error' vrl-run "$FX/broken.vrl"
check vrl-run-arith 'result={ "a": 3, "b": "ABC", "c": [1, 2, 3] }' vrl-run "$FX/arith.vrl"
# example.vrl is the vector-vrl crate's own test program; its header comments give the expected result.
check vrl-run-example 'result={ "bar": "foo", "baz": 4, "foo": "test" }' vrl-run "$VRL/example.vrl"

emit_ctrf "vector-kat" "$passed" "$failed" 0
