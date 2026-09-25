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
  tail -n 25 "/probe/log-$name.txt"
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
echo "--- getent passwd buildkite-agent"
getent passwd buildkite-agent
echo "--- /etc/systemd"
ls -la /etc/systemd 2>/dev/null || echo "no /etc/systemd"
echo "--- df"
df -h /
exit 0
