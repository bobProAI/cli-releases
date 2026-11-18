#!/bin/sh
# Installs ctx on a Mac with Apple silicon. Paste this into a terminal:
#
#   curl -fsSL https://raw.githubusercontent.com/bobProAI/cli-releases/main/ctx-install.sh | sh
#
# It reads the newest version from ctx-latest.txt, downloads that release of
# ctx from bobProAI/cli-releases, checks its sha256, and installs it as
# $HOME/.local/bin/ctx. Optional variables:
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

check_platform() {
  os=$(uname -s)
  arch=$(uname -m)
  if [ "$os" = Darwin ] && [ "$arch" = arm64 ]; then
    return
  fi
  if [ "$os" = Darwin ] && [ "$arch" = x86_64 ]; then
    fail "ctx needs macOS on Apple silicon (arm64), and this terminal reports an Intel Mac (x86_64). If this Mac has Apple silicon, the terminal runs under Rosetta. Open a terminal without Rosetta and run the install command again."
  fi
  fail "ctx needs macOS on Apple silicon (Darwin arm64), and this machine reports $os $arch. Run the install command on a Mac with Apple silicon."
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
  say "downloading ctx $version from $release_url"
  curl -fsSL -o "$download" "$release_url/ctx-darwin-arm64" ||
    fail "could not download $release_url/ctx-darwin-arm64. Check the internet connection and that release ctx-v$version exists at https://github.com/bobProAI/cli-releases/releases, then run the install command again."
  sums=$(curl -fsSL "$release_url/SHA256SUMS") ||
    fail "could not download $release_url/SHA256SUMS. Check the internet connection and run the install command again."
  expected=$(printf '%s\n' "$sums" | awk '$2 == "ctx-darwin-arm64" { print $1; exit }')
  if [ -z "$expected" ]; then
    fail "SHA256SUMS of ctx $version has no line for ctx-darwin-arm64, so nothing was installed. Tell the ctx maintainers."
  fi
  actual=$(shasum -a 256 "$download" | awk '{ print $1 }')
  if [ "$actual" != "$expected" ]; then
    fail "checksum mismatch: the downloaded ctx-darwin-arm64 does not match its sha256 in SHA256SUMS, so nothing was installed. Any earlier ctx still works. Run the install command again. If it fails again, tell the ctx maintainers."
  fi
  chmod 755 "$download"
  mv -f "$download" "$target"
  download=""
}

update_path() {
  case ":${PATH:-}:" in
    *":$bin_dir:"*) return ;;
  esac
  profile="$HOME/.zprofile"
  # $HOME and $PATH stay as text here. zsh expands them when it reads the file.
  line='export PATH="$HOME/.local/bin:$PATH"'
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
  installed=$("$target" --version) ||
    fail "$target is in place but did not run. Send the output above to the ctx maintainers."
  say "installed ctx $installed at $target"
}

main() {
  check_platform
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
