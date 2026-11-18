#!/bin/sh
# Installs ctx on a Mac with Apple silicon or on Linux x64. Paste this into a
# terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/bobProAI/cli-releases/main/ctx-install.sh | sh
#
# It reads the newest version from ctx-latest.txt, downloads that release of
# ctx for this machine from bobProAI/cli-releases, checks its sha256, and
# installs it as $HOME/.local/bin/ctx. Optional variables:
#
#   CTX_VERSION       installs this version, such as 0.1.0, instead of the newest
#   CTX_RAW_BASE      replaces https://raw.githubusercontent.com/bobProAI/cli-releases/main
#   CTX_RELEASE_BASE  replaces https://github.com/bobProAI/cli-releases/releases/download
#
# The two base variables let a test point the script at a local server.
# All work sits in functions, and the last line calls main. So a download
# of this script that stops early runs nothing.
set -eu

say() {
  printf 'ctx install: %s\n' "$1"
}

fail() {
  printf 'ctx install: %s\n' "$1" >&2
  exit 1
}

# Removes a partial download when the script stops early.
cleanup() {
  if [ -n "${download:-}" ]; then
    rm -f "$download"
  fi
}

# Sets asset to the release binary for this machine. Two platforms have one.
# Every other machine stops here, before any download.
check_platform() {
  os=$(uname -s)
  arch=$(uname -m)
  if [ "$os" = Darwin ] && [ "$arch" = arm64 ]; then
    asset=ctx-darwin-arm64
    return
  fi
  if [ "$os" = Linux ] && [ "$arch" = x86_64 ]; then
    asset=ctx-linux-x64
    return
  fi
  supported="ctx runs on macOS on Apple silicon (Darwin arm64) and on Linux x64 (Linux x86_64)"
  if [ "$os" = Darwin ] && [ "$arch" = x86_64 ]; then
    fail "$supported, and this terminal reports an Intel Mac (Darwin x86_64). If this Mac has Apple silicon, the terminal runs under Rosetta. Open a terminal without Rosetta and run the install command again."
  fi
  fail "$supported, and this machine reports $os $arch. Run the install command on one of those two platforms."
}

# Sets sha256_tool to the tool that checks the download. macOS ships shasum.
# Linux has sha256sum from coreutils, and some images have only shasum.
check_sha256_tool() {
  if [ "$os" = Linux ] && command -v sha256sum >/dev/null 2>&1; then
    sha256_tool=sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    sha256_tool=shasum
  elif [ "$os" = Linux ]; then
    fail "found neither sha256sum nor shasum, so the download cannot be checked. Install coreutils, which holds sha256sum, and run the install command again."
  else
    fail "found no shasum, so the download cannot be checked. macOS ships it in /usr/bin. Put /usr/bin on the PATH and run the install command again."
  fi
}

read_version() {
  if [ -n "${CTX_VERSION:-}" ]; then
    version=$CTX_VERSION
    bad_version="CTX_VERSION is \"$version\", which is not a version such as 0.1.0. Set CTX_VERSION to a version such as 0.1.0, or unset it to install the newest version."
  else
    latest_url="$raw_base/ctx-latest.txt"
    version=$(curl -fsSL "$latest_url") ||
      fail "could not read the newest version from $latest_url. Check the internet connection and run the install command again."
    bad_version="$latest_url gave \"$version\", which is not a version such as 0.1.0. Check the internet connection and run the install command again."
  fi
  if ! CTX_CHECK=$version awk 'BEGIN { exit !(ENVIRON["CTX_CHECK"] ~ /^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$/) }'; then
    fail "$bad_version"
  fi
}

install_binary() {
  bin_dir="$HOME/.local/bin"
  target="$bin_dir/ctx"
  release_url="$release_base/ctx-v$version"
  mkdir -p "$bin_dir" ||
    fail "could not create $bin_dir. Check that you own $HOME/.local, then run the install command again."
  if [ ! -w "$bin_dir" ]; then
    fail "cannot write to $bin_dir. Check that you own it, then run the install command again."
  fi

  # The download sits next to the target, so the mv below is a rename. A run
  # that stops before it leaves any earlier ctx in place and working.
  download="$bin_dir/.ctx-download-$$"
  say "downloading ctx $version ($asset) from $release_url"
  curl -fsSL -o "$download" "$release_url/$asset" ||
    fail "could not download $release_url/$asset. Check the internet connection and that the release ctx-v$version at https://github.com/bobProAI/cli-releases/releases has the file $asset, then run the install command again."
  sums=$(curl -fsSL "$release_url/SHA256SUMS") ||
    fail "could not download $release_url/SHA256SUMS. Check the internet connection and run the install command again."
  expected=$(printf '%s\n' "$sums" | awk -v name="$asset" '$2 == name { print $1; exit }')
  if [ -z "$expected" ]; then
    fail "SHA256SUMS of ctx $version has no line for $asset, so nothing was installed. Tell the ctx maintainers."
  fi
  if [ "$sha256_tool" = sha256sum ]; then
    actual=$(sha256sum "$download" | awk '{ print $1 }')
  else
    actual=$(shasum -a 256 "$download" | awk '{ print $1 }')
  fi
  if [ "$actual" != "$expected" ]; then
    fail "checksum mismatch: the downloaded $asset does not match its sha256 in SHA256SUMS, so nothing was installed. Any earlier ctx still works. Run the install command again. If it fails again, tell the ctx maintainers."
  fi
  chmod 755 "$download"
  mv -f "$download" "$target"
  download=""
}

update_path() {
  case ":${PATH:-}:" in
    *":$bin_dir:"*) return ;;
  esac
  # $HOME and $PATH stay as text here. The shell expands them when it reads
  # the line.
  line='export PATH="$HOME/.local/bin:$PATH"'
  # Linux has no one startup file that every shell reads, and a CI job reads
  # none. So on Linux the script changes no file and says what to add.
  if [ "$os" = Linux ]; then
    say "$bin_dir is not on the PATH. Run ctx as $target, or add this line to the startup file of your shell, such as $HOME/.bashrc, and open a new terminal: $line"
    return
  fi
  profile="$HOME/.zprofile"
  if [ -f "$profile" ] && grep -qxF "$line" "$profile"; then
    say "$profile already puts $bin_dir on the PATH. Open a new terminal to use ctx."
    return
  fi
  # A profile whose last line has no newline gets one first.
  newline=""
  if [ -s "$profile" ] && [ -n "$(tail -c 1 "$profile")" ]; then
    newline="
"
  fi
  printf '%s%s\n' "$newline" "$line" >>"$profile" ||
    fail "could not write $profile. Add this line to it, then open a new terminal: $line"
  say "added $bin_dir to the PATH in $profile. Open a new terminal to use ctx."
}

print_version() {
  if ! installed=$("$target" --version); then
    if [ "$os" = Linux ]; then
      fail "$target is in place but did not run. ctx for Linux needs glibc, so it does not run on Alpine or another system with musl. On any other system, send the output above to the ctx maintainers."
    fi
    fail "$target is in place but did not run. Send the output above to the ctx maintainers."
  fi
  say "installed ctx $installed at $target"
}

main() {
  check_platform
  check_sha256_tool
  if [ -z "${HOME:-}" ]; then
    fail "HOME is not set. Open a new terminal and run the install command again."
  fi
  raw_base=${CTX_RAW_BASE:-https://raw.githubusercontent.com/bobProAI/cli-releases/main}
  release_base=${CTX_RELEASE_BASE:-https://github.com/bobProAI/cli-releases/releases/download}
  raw_base=${raw_base%/}
  release_base=${release_base%/}
  download=""
  trap cleanup EXIT
  trap 'exit 1' HUP INT TERM
  read_version
  install_binary
  update_path
  print_version
}

main "$@"
