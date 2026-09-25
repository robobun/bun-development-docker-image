#!/bin/sh
# Probe: requests to apt.llvm.org fail when a lookup gives an IPv6 address only.
# Does one IPv4 lookup, written to /etc/hosts for the build step, stop that?
# Each round, with the name NOT pinned:
#   A  curl as the generated script calls it, apt.llvm.org
#   C  wget as check_url() of llvm.sh calls it, apt.llvm.org
#   D  curl, deb.debian.org   (control: another host on the same CDN)
#   E  curl, github.com       (control: a host on another network)
# and with the name pinned in /etc/hosts:
#   G  the same as A          H  the same as C
set -u

rounds=${1:-150}
pause=${2:-5}
host=apt.llvm.org
mkdir -p /probe/norc
: > /probe/norc/.curlrc
: > /probe/norc/wgetrc

pin=""
lookups=0
while [ -z "$pin" ] && [ "$lookups" -lt 20 ]; do
  lookups=$((lookups + 1))
  pin=$(getent ahostsv4 "$host" | awk 'NR == 1 { print $1 }')
  [ -n "$pin" ] || sleep 2
done
echo "pin: $host -> ${pin:-NONE} after $lookups lookups"
[ -n "$pin" ] || exit 0

cp /etc/hosts /probe/hosts.orig
pinned() { { cat /probe/hosts.orig; echo "$pin $host"; } > /etc/hosts || echo "pin: cannot write /etc/hosts"; }
unpinned() { cat /probe/hosts.orig > /etc/hosts || echo "pin: cannot write /etc/hosts"; }
pinned
echo "pin: with the pin, getent ahosts gives: $(getent ahosts "$host" | awk '{print $1}' | sort -u | tr '\n' ' ')"
unpinned

a=0; c=0; d=0; e=0; g=0; h=0
round=0
say() {
  grep -i -E 'unreachable|refused|timed out|reset|unable|giving up|could not|Trying|Connecting to|resolve' "$1" | head -n 4 | sed "s/^/pin:     /"
}
get() {
  CURL_HOME=/probe/norc curl --verbose --fail --silent --show-error --location --retry 3 --output /dev/null "$1" > /probe/last.log 2>&1
}
head_request() {
  WGETRC=/probe/norc/wgetrc wget --method=HEAD --timeout=15 --tries=3 "$1" > /probe/last.log 2>&1
}

while [ "$round" -lt "$rounds" ]; do
  round=$((round + 1))
  now=$(date -u +%H:%M:%S)

  unpinned
  get "https://$host/llvm.sh" || { a=$((a + 1)); echo "pin: $now round $round A curl $host FAILED"; say /probe/last.log; }
  head_request "https://$host/trixie/" || { c=$((c + 1)); echo "pin: $now round $round C wget $host FAILED"; say /probe/last.log; }
  get https://deb.debian.org/debian/dists/trixie/InRelease || { d=$((d + 1)); echo "pin: $now round $round D curl deb.debian.org FAILED"; say /probe/last.log; }
  get https://github.com/robots.txt || { e=$((e + 1)); echo "pin: $now round $round E curl github.com FAILED"; say /probe/last.log; }

  pinned
  get "https://$host/llvm.sh" || { g=$((g + 1)); echo "pin: $now round $round G curl $host PINNED FAILED"; say /probe/last.log; }
  head_request "https://$host/trixie/" || { h=$((h + 1)); echo "pin: $now round $round H wget $host PINNED FAILED"; say /probe/last.log; }

  [ $((round % 30)) -eq 0 ] && echo "pin: $now round $round of $rounds: not pinned A=$a C=$c, controls D=$d E=$e, pinned G=$g H=$h"
  sleep "$pause"
done
unpinned

echo "pin: RESULT rounds=$rounds: not pinned: curl A=$a wget C=$c; controls: deb.debian.org D=$d github.com E=$e; pinned: curl G=$g wget H=$h"
exit 0
