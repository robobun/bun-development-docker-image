#!/bin/sh
# Probe of the bake script that oven-sh/bun generates for the Debian image.
#   probe.sh whole   run the script once, cut before the prefetch
#   probe.sh build   build bun (debug) with what the script installed
#   probe.sh twice   run the same script again: is it safe to run twice?
set -u

mode=$1
cd /workspace/bun
commit=$(git rev-parse HEAD)
echo "probe[$mode]: bun commit $commit, $(uname -m)"

generate() {
  # The Debian image of this architecture, with the cross-compile tools of the
  # `build` role left out.
  bake=$(bun -e '
    import { generateImage, images } from "./scripts/build/ci-images/spec.ts";
    const arch = process.arch === "arm64" ? "aarch64" : "x64";
    const image = images.find(i => i.os === "linux" && i.distro === "debian" && i.arch === arch);
    if (!image) throw new Error("no debian image for " + arch);
    console.log(generateImage({ ...image, role: "test" }, "/probe/root").directory);
  ') || { echo "probe[$mode]: generateImage failed"; exit 1; }
  grep -q '^# ---- prefetch$' "$bake/bootstrap.sh" || { echo "probe[$mode]: no prefetch banner"; exit 1; }
  sed '/^# ---- prefetch$/,$d' "$bake/bootstrap.sh" > "$bake/bootstrap-cut.sh"
  echo "probe[$mode]: sections that run: $(grep '^# ---- ' "$bake/bootstrap-cut.sh" | cut -c8- | tr '\n' ' ')"
}

case "$mode" in
  whole)
    generate
    start=$(date +%s)
    sh -x "$bake/bootstrap-cut.sh" "$commit" probe-image > /probe/log-whole.txt 2>&1
    status=$?
    end=$(date +%s)
    tail -n 80 /probe/log-whole.txt
    echo "probe[whole]: exit=$status after $((end - start))s"
    df -h /
    exit "$status"
    ;;
  build)
    start=$(date +%s)
    # A login shell reads /etc/profile.d/bun-ci.sh, which is where the script puts PATH, RUSTUP_HOME and CARGO_HOME.
    sh -lc 'cd /workspace/bun && echo "PATH=$PATH" && bun --version && clang --version | head -1 && rustc --version && bun run build' > /probe/log-build.txt 2>&1
    status=$?
    end=$(date +%s)
    tail -n 80 /probe/log-build.txt
    echo "probe[build]: bun run build exit=$status after $((end - start))s"
    if [ "$status" -eq 0 ]; then
      ls -la build/debug/bun-debug
      build/debug/bun-debug --version
      echo "probe[build]: bun-debug --version exit=$?"
    fi
    df -h /
    exit "$status"
    ;;
  twice)
    generate
    sh -x "$bake/bootstrap-cut.sh" "$commit" probe-image > /probe/log-twice.txt 2>&1
    status=$?
    tail -n 15 /probe/log-twice.txt
    echo "probe[twice]: the second run exit=$status"
    exit 0
    ;;
  *)
    echo "usage: probe.sh whole|build|twice"
    exit 1
    ;;
esac
