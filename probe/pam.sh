#!/bin/sh
# Probe: the `ulimits` section of the generated script writes limits that a
# container without CAP_SYS_RESOURCE cannot raise. Debian's su and sudo call
# pam_limits. Do they still work afterwards?
#   pam.sh build          check, run the ulimits section, check again
#   pam.sh check <label>  check only
set -u
mode=$1

check() {
  label=$1
  echo "pam[$label]: CapEff $(awk '/CapEff/ {print $2}' /proc/self/status)"
  prlimit --memlock --sigpending --msgqueue --nofile --nproc --core --noheadings -o RESOURCE,SOFT,HARD | sed "s/^/pam[$label]:   limit /"
  su probeuser -c 'echo su-ok' > /tmp/pam.log 2>&1
  status=$?
  echo "pam[$label]: su probeuser exit=$status output: $(tr '\n' ' ' < /tmp/pam.log)"
  sudo -n -u probeuser true > /tmp/pam.log 2>&1
  status=$?
  echo "pam[$label]: sudo -u probeuser exit=$status output: $(tr '\n' ' ' < /tmp/pam.log)"
  sudo -n true > /tmp/pam.log 2>&1
  status=$?
  echo "pam[$label]: sudo as root exit=$status output: $(tr '\n' ' ' < /tmp/pam.log)"
}

case "$mode" in
  build)
    useradd --system --shell /bin/sh probeuser
    grep -n pam_limits /etc/pam.d/su /etc/pam.d/sudo /etc/pam.d/common-session* | sed 's/^/pam[build]:   before: /'
    check before-ulimits
    cd /workspace/bun
    bake=$(bun -e '
      import { generateImage, images } from "./scripts/build/ci-images/spec.ts";
      const arch = process.arch === "arm64" ? "aarch64" : "x64";
      const image = images.find(i => i.os === "linux" && i.distro === "debian" && i.arch === arch);
      console.log(generateImage({ ...image, role: "test" }, "/probe/root").directory);
    ') || { echo "pam[build]: generateImage failed"; exit 1; }
    script="$bake/bootstrap.sh"
    {
      sed '/^# ---- /,$d' "$script"
      sed -n '/^# ---- ulimits$/,/^# ---- /p' "$script" | sed '$d'
    } > "$bake/run-ulimits.sh"
    echo "pam[build]: the section has $(wc -l < "$bake/run-ulimits.sh") lines, banner: $(grep -c '^# ---- ulimits$' "$bake/run-ulimits.sh")"
    # The `packages` section, which runs first in the real script, installs systemd.
    mkdir -p /etc/systemd
    sh "$bake/run-ulimits.sh" "$(git rev-parse HEAD)" probe-image
    echo "pam[build]: ulimits section exit=$?"
    check after-ulimits-in-build
    ;;
  check)
    check "$2"
    ;;
esac
exit 0
