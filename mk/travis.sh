#!/usr/bin/env bash
#
# Copyright 2015 Brian Smith.
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHORS DISCLAIM ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY
# SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
# OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
# CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

set -eux -o pipefail
IFS=$'\n\t'

printenv

if [[ ! "$TARGET_X" =~ ^(x86_64-|i686-) ]]; then
  ! command -v cross 1>/dev/null && cargo install cross
  CARGO="cross"
  echo -e "[target.$TARGET_X]\nrunner = \"qemu-system\"" > Cross.toml
  cat Cross.toml
else
  CARGO="cargo"

  if [[ ! -z "${CC_X-}" ]]; then
    export CC=$CC_X
    $CC --version
  else
    cc --version
  fi

  cargo version
  rustc --version

  if [[ "$MODE_X" == "RELWITHDEBINFO" ]]; then
    target_dir=target/$TARGET_X/release
  else
    target_dir=target/$TARGET_X/debug
  fi
fi

if [[ "$MODE_X" == "RELWITHDEBINFO" ]]; then
  mode=--release
fi

$CARGO test -vv -j2 ${mode-} ${FEATURES_X-} --target=$TARGET_X

if [[ "$KCOV" == "1" ]]; then
  # kcov reports coverage as a percentage of code *linked into the executable*
  # (more accurately, code that has debug info linked into the executable), not
  # as a percentage of source code. Thus, any code that gets discarded by the
  # linker due to lack of usage isn't counted at all. Thus, we have to re-link
  # with "-C link-dead-code" to get accurate code coverage reports.
  # Alternatively, we could link pass "-C link-dead-code" in the "$CARGO test"
  # step above, but then "$CARGO test" we wouldn't be testing the configuration
  # we expect people to use in production.
  $CARGO clean
  RUSTFLAGS="-C link-dead-code" \
    $CARGO test -vv --no-run -j2  ${mode-} ${FEATURES_X-} --target=$TARGET_X
  mk/travis-install-kcov.sh
  for test_exe in `find target/$TARGET_X/debug -maxdepth 1 -executable -type f`; do
    ${HOME}/kcov-${TARGET_X}/bin/kcov \
      --verify \
      --coveralls-id=$TRAVIS_JOB_ID \
      --exclude-path=/usr/include \
      --include-pattern="ring/crypto,ring/src,ring/tests" \
      target/kcov \
      $test_exe
  done
fi

# Verify that `$CARGO build`, independent from `$CARGO test`, works; i.e. verify
# that non-test builds aren't trying to use test-only features. For platforms
# for which we don't run tests, this is the only place we even verify that the
# code builds.
$CARGO build -vv -j2 ${mode-} ${FEATURES_X-} --target=$TARGET_X

echo end of mk/travis.sh
