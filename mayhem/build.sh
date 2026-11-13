#!/usr/bin/env bash
#
# mayhem/build.sh — builds the cargo-fuzz targets (ASan via RUSTFLAGS) into /mayhem/<target> and
# the known-answer probe (normal flags) that mayhem/test.sh asserts against.
#
# Runs in the commit image as `mayhem` in /mayhem. The toolchain and the cargo registry/git
# cache live under $CARGO_HOME=/opt/toolchains/rust/cargo (Dockerfile ENV), so the air-gapped
# re-run (CARGO_NET_OFFLINE=true, set by the runtime — never `--offline` here) resolves from it.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# Upstream pins rust-toolchain.toml at the repo root; RUSTUP_TOOLCHAIN (Dockerfile ENV) wins over it.
export RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-nightly-2026-10-20}"

cd "${SRC:-/mayhem}"

# DWARF < 4 (SPEC §6.2 item 10), threaded through RUSTFLAGS on the fuzz build only.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -Zdwarf-version=3}"
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address -Cforce-frame-pointers ${RUST_DEBUG_FLAGS}"

# rustc ignores the clang-style $SANITIZER_FLAGS; C deps (onig_sys, zstd-sys) get its ASan part via cc-rs.
# UBSan stays out: rustc doesn't link its runtime, so instrumented C++ (libfuzzer-sys) would not link.
case "${SANITIZER_FLAGS-fsanitize=address}" in
  *address*)
    export CFLAGS="${CFLAGS:-} -fsanitize=address -fno-omit-frame-pointer"
    export CXXFLAGS="${CXXFLAGS:-} -fsanitize=address -fno-omit-frame-pointer"
    ;;
esac

FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# Leak detection off at build time (SPEC §6.2 item 15): link mayhem/lsan_off.cc into every fuzz binary.
# The object lives under the gitignored fuzz/target dir; link-arg paths must be absolute.
mkdir -p "$PWD/$FUZZ_DIR/target"
lsan_off="$PWD/$FUZZ_DIR/target/lsan_off.o"
${CXX:-clang++} -fsanitize=address -fno-omit-frame-pointer -g -gdwarf-3 -c mayhem/lsan_off.cc -o "$lsan_off"
export RUSTFLAGS="$RUSTFLAGS -C link-arg=$lsan_off"

FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$PWD/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Known-answer probe for test.sh: the project's NORMAL flags (no sanitizer, no fuzz cfg).
echo "=== known-answer probe (normal flags) ==="
(
  unset RUSTFLAGS CFLAGS CXXFLAGS
  cargo build --release --manifest-path mayhem/kat/Cargo.toml
)
kat="$PWD/mayhem/kat/target/release/vector-kat"
[ -x "$kat" ] || { echo "ERROR: probe not built at $kat" >&2; exit 1; }
file "$kat" | grep -q 'dynamically linked' || { echo "ERROR: probe is not dynamically linked, so the sabotage check cannot neuter it" >&2; exit 1; }

echo "build.sh complete"
