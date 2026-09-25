#!/bin/sh
# Installs the toolchain that builds and tests Bun, inside `docker build`.
#
# oven-sh/bun generates the script that its CI machines are baked with, from
# scripts/build/ci-images/spec.ts (`bun run ci:images`). It replaced
# scripts/bootstrap.sh in oven-sh/bun#43608. This file generates that script
# for Debian 13 on this architecture and runs it, with two differences from a
# CI bake:
#
# - `role: "test"` leaves out the cross-compile SDKs and sysroots. Only the
#   one CI machine that compiles every target needs them.
# - The script is cut before its `prefetch` section. That section and the ones
#   after it need a Docker daemon and an init system. "Testing a change before
#   CI does" in scripts/build/ci-images/CLAUDE.md says to cut there.
#
# Run it as root, from the root of a checkout of oven-sh/bun. It needs `bun`
# on PATH to run the generator. The generated script cannot run twice.
set -eu

spec=scripts/build/ci-images/spec.ts
if ! [ -f "$spec" ]; then
  echo "install-toolchain: $(pwd) has no $spec. A ref older than oven-sh/bun#43608 cannot be built." >&2
  exit 1
fi

bake_root=$(mktemp -d -p /var/tmp)
bake=$(BAKE_ROOT="$bake_root" bun -e '
  import { generateImage, images } from "./scripts/build/ci-images/spec.ts";
  const arch = process.arch === "arm64" ? "aarch64" : "x64";
  const image = images.find(i => i.os === "linux" && i.distro === "debian" && i.arch === arch);
  if (!image) throw new Error("spec.ts has no Debian image for " + arch);
  console.log(generateImage({ ...image, role: "test" }, process.env.BAKE_ROOT).directory);
')

if ! grep -q '^# ---- prefetch$' "$bake/bootstrap.sh"; then
  echo "install-toolchain: the generated script has no \"# ---- prefetch\" section to cut at." >&2
  exit 1
fi
sed '/^# ---- prefetch$/,$d' "$bake/bootstrap.sh" > "$bake/toolchain.sh"
echo "install-toolchain: sections: $(grep '^# ---- ' "$bake/toolchain.sh" | cut -c8- | tr '\n' ' ')"

sh "$bake/toolchain.sh" "$(git rev-parse HEAD)" bun-development-docker-image
rm -rf "$bake_root"

# The script writes the node-gyp header cache for CI's agent user alone. Root
# gets a copy, as bootstrap.sh gave it, so that a native addon builds without
# a download of the headers.
agent_home=$(getent passwd buildkite-agent | cut -d: -f6)
mkdir -p /root/.cache
cp -R "$agent_home/.cache/node-gyp" /root/.cache/
