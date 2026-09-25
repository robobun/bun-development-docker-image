#!/bin/sh
# Probe: apt.llvm.org refuses some connections from GitHub runners.
# Each round runs the two unprotected requests of the LLVM install, exactly as
# they are written, with and without retry defaults from rc files:
#   A  the generated script's download:  curl --retry 3 ...        (no rc file)
#   B  the same command, with `retry-connrefused` in $CURL_HOME/.curlrc
#   C  check_url() of llvm.sh:           wget --method=HEAD --tries=3 (no rc file)
#   D  the same command, with `retry_connrefused = on` in $WGETRC
# A failed request prints what the tool said, so the error is on record.
set -u

rounds=${1:-150}
pause=${2:-10}
mkdir -p /probe/rc /probe/norc
printf 'retry-connrefused\n' > /probe/rc/.curlrc
printf 'retry_connrefused = on\n' > /probe/rc/wgetrc
: > /probe/norc/.curlrc
: > /probe/norc/wgetrc

a_fail=0
b_fail=0
c_fail=0
d_fail=0
round=0
url_script=https://apt.llvm.org/llvm.sh
url_head=https://apt.llvm.org/trixie/

say() {
  # The lines that name the error, from a verbose log.
  grep -i -E 'refused|unreachable|timed out|failed|reset|error|unable|giving up|retry|Trying|Connecting' "$1" | head -n 8 | sed "s/^/reach:     /"
}

while [ "$round" -lt "$rounds" ]; do
  round=$((round + 1))
  now=$(date -u +%H:%M:%S)

  CURL_HOME=/probe/norc curl --verbose --fail --silent --show-error --location --retry 3 --output /dev/null "$url_script" > /probe/a.log 2>&1
  status=$?
  if [ "$status" -ne 0 ]; then
    a_fail=$((a_fail + 1))
    echo "reach: $now round $round A curl (no rc) FAILED exit=$status"
    say /probe/a.log
  fi

  CURL_HOME=/probe/rc curl --verbose --fail --silent --show-error --location --retry 3 --output /dev/null "$url_script" > /probe/b.log 2>&1
  status=$?
  if [ "$status" -ne 0 ]; then
    b_fail=$((b_fail + 1))
    echo "reach: $now round $round B curl (curlrc retry-connrefused) FAILED exit=$status"
    say /probe/b.log
  elif grep -q -i -E 'retry|refused|could not connect' /probe/b.log; then
    echo "reach: $now round $round B curl (curlrc retry-connrefused) ok after a retry"
    say /probe/b.log
  fi

  WGETRC=/probe/norc/wgetrc wget --method=HEAD --timeout=15 --tries=3 "$url_head" > /probe/c.log 2>&1
  status=$?
  if [ "$status" -ne 0 ]; then
    c_fail=$((c_fail + 1))
    echo "reach: $now round $round C wget HEAD (no rc) FAILED exit=$status"
    say /probe/c.log
  fi

  WGETRC=/probe/rc/wgetrc wget --method=HEAD --timeout=15 --tries=3 "$url_head" > /probe/d.log 2>&1
  status=$?
  if [ "$status" -ne 0 ]; then
    d_fail=$((d_fail + 1))
    echo "reach: $now round $round D wget HEAD (wgetrc retry_connrefused) FAILED exit=$status"
    say /probe/d.log
  elif grep -q -i -E 'retrying|refused' /probe/d.log; then
    echo "reach: $now round $round D wget HEAD (wgetrc retry_connrefused) ok after a retry"
    say /probe/d.log
  fi

  [ $((round % 30)) -eq 0 ] && echo "reach: $now round $round of $rounds: failed A=$a_fail B=$b_fail C=$c_fail D=$d_fail"
  sleep "$pause"
done

echo "reach: RESULT rounds=$rounds pause=${pause}s failed: A curl no rc=$a_fail, B curl with curlrc=$b_fail, C wget no rc=$c_fail, D wget with wgetrc=$d_fail"
curl --version | head -n 1
wget --version | head -n 1
exit 0
