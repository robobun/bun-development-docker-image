#!/bin/sh
# Probe: requests to apt.llvm.org from `docker build` fail when a lookup gives
# an IPv6 address only ("Network is unreachable"). Does forcing IPv4 stop it?
# Each round runs the same request with the tool's defaults and with IPv4
# forced through the tool's own configuration file:
#   A  curl as the generated script calls it      E  + `ipv4` in .curlrc
#   C  wget as check_url() of llvm.sh calls it     F  + `inet4_only = on` in wgetrc
#   P  apt-get update of the LLVM source           Q  + Acquire::ForceIPv4 "true"
# It also records what one lookup of the name returns in each round.
set -u

rounds=${1:-120}
pause=${2:-8}
mkdir -p /probe/v4 /probe/norc /probe/apt
printf 'ipv4\n' > /probe/v4/.curlrc
printf 'inet4_only = on\n' > /probe/v4/wgetrc
: > /probe/norc/.curlrc
: > /probe/norc/wgetrc
echo 'deb [trusted=yes] https://apt.llvm.org/trixie/ llvm-toolchain-trixie-23 main' > /probe/apt/llvm.list

echo "reach: resolv.conf: $(grep -v '^#' /etc/resolv.conf | tr '\n' ';')"
echo "reach: IPv6 addresses of this container: $(awk '{print $1 " " $6}' /proc/net/if_inet6 2>/dev/null | tr '\n' ';')"
echo "reach: IPv6 routes: $(wc -l < /proc/net/ipv6_route 2>/dev/null) lines in /proc/net/ipv6_route"

a_fail=0; e_fail=0; c_fail=0; f_fail=0; p_fail=0; q_fail=0
only6=0; only4=0; both=0; none=0
round=0
url_script=https://apt.llvm.org/llvm.sh
url_head=https://apt.llvm.org/trixie/

say() {
  grep -i -E 'unreachable|refused|timed out|failed|reset|unable|giving up|could not|Trying|Connecting|resolve' "$1" | head -n 5 | sed "s/^/reach:     /"
}
apt_update() {
  # One update of the LLVM source alone. apt-get exits 0 on a failed fetch unless it is told to count it as an error.
  apt-get update "$@" -o APT::Update::Error-Mode=any -o Dir::Etc::sourcelist=/probe/apt/llvm.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
}

while [ "$round" -lt "$rounds" ]; do
  round=$((round + 1))
  now=$(date -u +%H:%M:%S)

  addresses=$(getent ahosts apt.llvm.org 2>/dev/null | awk '{print $1}' | sort -u)
  v6=$(printf '%s\n' "$addresses" | grep -c ':')
  v4=$(printf '%s\n' "$addresses" | grep -c -E '^[0-9]+\.')
  if [ "$v4" -gt 0 ] && [ "$v6" -gt 0 ]; then both=$((both + 1)); family=both
  elif [ "$v6" -gt 0 ]; then only6=$((only6 + 1)); family=ipv6-only
  elif [ "$v4" -gt 0 ]; then only4=$((only4 + 1)); family=ipv4-only
  else none=$((none + 1)); family=none; fi
  [ "$family" = ipv4-only ] || echo "reach: $now round $round lookup gave $family: $(printf '%s' "$addresses" | tr '\n' ' ')"

  CURL_HOME=/probe/norc curl --verbose --fail --silent --show-error --location --retry 3 --output /dev/null "$url_script" > /probe/a.log 2>&1 \
    || { a_fail=$((a_fail + 1)); echo "reach: $now round $round A curl (defaults) FAILED"; say /probe/a.log; }
  CURL_HOME=/probe/v4 curl --verbose --fail --silent --show-error --location --retry 3 --output /dev/null "$url_script" > /probe/e.log 2>&1 \
    || { e_fail=$((e_fail + 1)); echo "reach: $now round $round E curl (ipv4 in .curlrc) FAILED"; say /probe/e.log; }
  WGETRC=/probe/norc/wgetrc wget --method=HEAD --timeout=15 --tries=3 "$url_head" > /probe/c.log 2>&1 \
    || { c_fail=$((c_fail + 1)); echo "reach: $now round $round C wget HEAD (defaults) FAILED"; say /probe/c.log; }
  WGETRC=/probe/v4/wgetrc wget --method=HEAD --timeout=15 --tries=3 "$url_head" > /probe/f.log 2>&1 \
    || { f_fail=$((f_fail + 1)); echo "reach: $now round $round F wget HEAD (inet4_only in wgetrc) FAILED"; say /probe/f.log; }
  apt_update > /probe/p.log 2>&1 \
    || { p_fail=$((p_fail + 1)); echo "reach: $now round $round P apt-get update (defaults) FAILED"; say /probe/p.log; }
  apt_update -o Acquire::ForceIPv4=true > /probe/q.log 2>&1 \
    || { q_fail=$((q_fail + 1)); echo "reach: $now round $round Q apt-get update (ForceIPv4) FAILED"; say /probe/q.log; }
  [ "$round" -eq 1 ] && tail -n 6 /probe/p.log | sed 's/^/reach:   apt says: /'

  [ $((round % 30)) -eq 0 ] && echo "reach: $now round $round of $rounds: failed A=$a_fail E=$e_fail C=$c_fail F=$f_fail P=$p_fail Q=$q_fail; lookups ipv4-only=$only4 both=$both ipv6-only=$only6 none=$none"
  sleep "$pause"
done

echo "reach: RESULT rounds=$rounds: curl defaults A=$a_fail, curl ipv4 E=$e_fail, wget defaults C=$c_fail, wget inet4_only F=$f_fail, apt defaults P=$p_fail, apt ForceIPv4 Q=$q_fail"
echo "reach: LOOKUPS rounds=$rounds: ipv4-only=$only4 both=$both ipv6-only=$only6 none=$none"
exit 0
