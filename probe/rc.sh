#!/bin/sh
# Probe: requests to apt.llvm.org fail when a lookup gives an IPv6 address only.
# Do the tools' own configuration files stop that, with no change to the
# commands? Each round runs, from a build step:
#   A  curl as the generated script calls it, tool defaults
#   C  wget as check_url() of llvm.sh calls it, tool defaults
#   J  the same as A, with CURL_HOME/.curlrc: ipv4, retry-all-errors
#   K  the same as C, with WGETRC: inet4_only, retry_on_host_error, retry_connrefused
set -u

rounds=${1:-150}
pause=${2:-5}
mkdir -p /probe/norc /probe/rc
: > /probe/norc/.curlrc
: > /probe/norc/wgetrc
printf 'ipv4\nretry-all-errors\n' > /probe/rc/.curlrc
printf 'inet4_only = on\nretry_on_host_error = on\nretry_connrefused = on\n' > /probe/rc/wgetrc

a=0; c=0; j=0; k=0; j_retried=0; k_retried=0
round=0
say() {
  grep -i -E 'unreachable|refused|timed out|reset|unable|giving up|could not|Trying|Connecting to|resolv|retry' "$1" | head -n 6 | sed "s/^/rc:     /"
}

while [ "$round" -lt "$rounds" ]; do
  round=$((round + 1))
  now=$(date -u +%H:%M:%S)

  CURL_HOME=/probe/norc curl --verbose --fail --silent --show-error --location --retry 3 --output /dev/null https://apt.llvm.org/llvm.sh > /probe/last.log 2>&1 \
    || { a=$((a + 1)); echo "rc: $now round $round A curl defaults FAILED"; say /probe/last.log; }
  WGETRC=/probe/norc/wgetrc wget --method=HEAD --timeout=15 --tries=3 https://apt.llvm.org/trixie/ > /probe/last.log 2>&1 \
    || { c=$((c + 1)); echo "rc: $now round $round C wget defaults FAILED"; say /probe/last.log; }

  if CURL_HOME=/probe/rc curl --verbose --fail --silent --show-error --location --retry 3 --output /dev/null https://apt.llvm.org/llvm.sh > /probe/last.log 2>&1; then
    if grep -q -i -E 'could not resolve|will retry|unreachable' /probe/last.log; then j_retried=$((j_retried + 1)); echo "rc: $now round $round J curl with rc ok after a retry"; say /probe/last.log; fi
  else
    j=$((j + 1)); echo "rc: $now round $round J curl with rc FAILED"; say /probe/last.log
  fi
  if WGETRC=/probe/rc/wgetrc wget --method=HEAD --timeout=15 --tries=3 https://apt.llvm.org/trixie/ > /probe/last.log 2>&1; then
    if grep -q -i -E 'retrying|unable to resolve|unreachable' /probe/last.log; then k_retried=$((k_retried + 1)); echo "rc: $now round $round K wget with rc ok after a retry"; say /probe/last.log; fi
  else
    k=$((k + 1)); echo "rc: $now round $round K wget with rc FAILED"; say /probe/last.log
  fi

  [ $((round % 30)) -eq 0 ] && echo "rc: $now round $round of $rounds: defaults A=$a C=$c, with rc J=$j K=$k (ok after a retry: J=$j_retried K=$k_retried)"
  sleep "$pause"
done

echo "rc: RESULT rounds=$rounds: defaults: curl A=$a wget C=$c; with rc files: curl J=$j wget K=$k; ok after a retry: curl J=$j_retried wget K=$k_retried"
exit 0
