#!/usr/bin/env bash
# Run as an unprivileged user in a dedicated Linux arm64 build environment.
set -euo pipefail
[[ $# == 1 ]] || { echo 'Usage: build-fex-comparison.sh NEW_OUTPUT_DIRECTORY' >&2; exit 2; }
[[ $(uname -s) == Linux && $(uname -m) == aarch64 && $(id -u) != 0 ]] ||
  { echo 'Requires an unprivileged Linux aarch64 build environment' >&2; exit 2; }
for tool in git clang clang++ cmake ninja ld.lld sha256sum; do command -v "$tool" >/dev/null; done
export LC_ALL=C TZ=UTC GIT_TERMINAL_PROMPT=0
umask 077
mkdir -- "$1"
out=$(cd "$1" && pwd -P)
exec > >(tee "$out/build.log") 2>&1
set -x
uname -a
cat /etc/os-release
for tool in git clang clang++ cmake ninja ld.lld; do "$tool" --version; done
if command -v dpkg-query >/dev/null; then dpkg-query -W > "$out/packages.tsv"
elif command -v rpm >/dev/null; then rpm -qa | sort > "$out/packages.tsv"
fi
build() {
  local label=$1 ref=$2 sha=$3
  local src="$out/$label/source"
  mkdir -p "$out/$label"
  git init "$src"
  git -C "$src" remote add origin https://github.com/StonkGuy/FEX.git
  git -C "$src" -c http.sslVerify=true fetch --depth=1 origin "$ref"
  [[ $(git -C "$src" rev-parse FETCH_HEAD) == "$sha" ]]
  git -C "$src" checkout --detach "$sha"
  git -C "$src" -c protocol.allow=never -c protocol.https.allow=always -c http.sslVerify=true submodule update --init --recursive
  git -C "$src" submodule status --recursive > "$out/$label/submodules.txt"
  cmake -S "$src" -B "$out/$label/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DBUILD_STEAM_SUPPORT=ON -DBUILD_TESTING=OFF -DBUILD_THUNKS=OFF -DBUILD_FEXCONFIG=OFF \
    -DENABLE_LTO=OFF -DENABLE_ASSERTIONS=OFF -DCMAKE_CXX_SCAN_FOR_MODULES=OFF -DCMAKE_INSTALL_PREFIX=/usr
  cmake --build "$out/$label/build" --parallel 4
  DESTDIR="$out/$label/stage" cmake --install "$out/$label/build" --component Runtime
  (
    cd "$out/$label/stage"
    test -x usr/bin/FEX
    find . -type f -print0 | sort -z | xargs -0 sha256sum > "$out/$label/SHA256SUMS"
    find . -type l -printf '%p\t%l\n' | sort > "$out/$label/symlinks.tsv"
  )
}
build baseline 9d0a260cbf03f2ebc48f4d70c92ba713a91c3d32 9d0a260cbf03f2ebc48f4d70c92ba713a91c3d32
build pr20 refs/pull/20/head 97583564c7983321f974f867eeab52bf25702079
