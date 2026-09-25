#!/bin/sh
# Probe: run every section of the bake script that oven-sh/bun generates for
# the Debian image, one section at a time, in order, in this container.
# Record which sections work inside `docker build` and what each one costs.
# The probe never fails the build: the table at the end is the result.
set -u

cd /workspace/bun
commit=$(git rev-parse HEAD)
echo "probe: bun commit $commit"
echo "probe: uname -m $(uname -m)"
echo "probe: before any section: systemctl=$(command -v systemctl || echo -) /etc/systemd=$([ -d /etc/systemd ] && echo yes || echo no)"

# How often does apt.llvm.org accept a connection from this runner?
reach() {
  label=$1
  ok=0
  fail=0
  echo "probe: apt.llvm.org resolves to: $(getent ahosts apt.llvm.org | awk '{print $1}' | sort -u | tr '\n' ' ')"
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if out=$(curl --silent --show-error --output /dev/null --connect-timeout 15 --max-time 60 \
      --write-out '%{http_code} %{remote_ip} %{time_connect}s' https://apt.llvm.org/llvm.sh 2>&1); then
      ok=$((ok + 1))
      echo "probe: reach[$label] attempt $attempt: ok $out"
    else
      fail=$((fail + 1))
      echo "probe: reach[$label] attempt $attempt: FAILED $out"
    fi
    sleep 3
  done
  echo "probe: reach[$label] RESULT ok=$ok failed=$fail of 10"
}
reach start

# The Debian image of this architecture, with the cross-compile tools of the
# `build` role left out.
bake=$(bun -e '
  import { generateImage, images } from "./scripts/build/ci-images/spec.ts";
  const arch = process.arch === "arm64" ? "aarch64" : "x64";
  const image = images.find(i => i.os === "linux" && i.distro === "debian" && i.arch === arch);
  if (!image) throw new Error("no debian image for " + arch);
  console.log(generateImage({ ...image, role: "test" }, process.cwd()).directory);
') || { echo "probe: generateImage failed"; exit 0; }
echo "probe: bake directory $bake"
ls -la "$bake"

script="$bake/bootstrap.sh"
echo "probe: banners"
grep -n '^# ---- ' "$script"

# Split into the preamble and one file per section.
rm -rf /probe/sections && mkdir -p /probe/sections
awk -v out=/probe/sections '
  /^# ---- / { n++; file = sprintf("%s/%02d-%s", out, n, $3) }
  { if (n == 0) print > (out "/00-preamble"); else print > file }
' "$script"
ls /probe/sections

results=/probe/results.txt
: > "$results"
used() { df --output=used -k / | tail -1 | tr -d ' '; }

for section in /probe/sections/[0-9][0-9]-*; do
  name=$(basename "$section" | cut -d- -f2-)
  [ "$name" = preamble ] && continue
  case "$name" in
    prefetch | agent-service)
      printf '%-18s %-6s %6s %9s\n' "$name" skip - - >> "$results"
      continue
      ;;
    llvm) reach before-llvm ;;
  esac
  run="$bake/run-$name.sh"
  {
    cat /probe/sections/00-preamble
    # What earlier sections exported, as a login shell on a baked machine sees it.
    echo '[ -f /etc/profile.d/bun-ci.sh ] && . /etc/profile.d/bun-ci.sh'
    cat "$section"
  } > "$run"
  echo
  echo "================================================================"
  echo "probe: section $name"
  echo "================================================================"
  before=$(used)
  start=$(date +%s)
  sh "$run" "$commit" probe-image > "/probe/log-$name.txt" 2>&1
  status=$?
  end=$(date +%s)
  after=$(used)
  case "$name" in
    packages) grep -E '^Setting up (systemd|systemd-sysv|dbus|libpam-systemd|init-system-helpers)' "/probe/log-$name.txt" ;;
  esac
  tail -n 25 "/probe/log-$name.txt"
  echo "probe: after $name: systemctl=$(command -v systemctl || echo -)"
  printf '%-18s %-6s %5ss %8sMB\n' "$name" "exit=$status" "$((end - start))" "$(((after - before) / 1024))" >> "$results"
done

echo
echo "================================================================"
echo "probe: RESULTS (section, exit status, seconds, disk growth)"
echo "================================================================"
cat "$results"

echo
echo "probe: state after all sections"
for tool in bun node cmake ninja clang clang-23 ld.lld llvm-symbolizer rustc cargo go nasm ccache docker google-chrome age curl-h3 tailscale buildkite-agent ab gdb systemctl; do
  printf '%-16s %s\n' "$tool" "$(command -v "$tool" 2>/dev/null || echo -)"
done
echo "--- /etc/profile.d/bun-ci.sh"
cat /etc/profile.d/bun-ci.sh 2>/dev/null
echo "--- /usr/lib/llvm-*"
ls -d /usr/lib/llvm-* 2>/dev/null
echo "--- /opt"
ls -la /opt 2>/dev/null
echo "--- df"
df -h /

echo
echo "================================================================"
echo "probe: bun's configure, in a login shell (the environment the script wrote)"
echo "================================================================"
sh -lc 'cd /workspace/bun && echo "PATH=$PATH" && command -v clang cargo rustc bun node cmake; bun --version; clang --version | head -1; rustc --version; bun scripts/build.ts --profile=debug --configure-only' > /probe/log-configure.txt 2>&1
configure_status=$?
tail -n 60 /probe/log-configure.txt
echo "probe: configure exit=$configure_status"
exit 0
