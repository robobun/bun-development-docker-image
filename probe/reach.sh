#!/bin/sh
# Probe: how often, and for how long, does apt.llvm.org refuse a connection
# from a `docker build` step on this runner? One round every 20 seconds.
# Each round makes the three requests that llvm.sh makes before it calls apt.
set -u

rounds=${1:-120}
pause=${2:-20}
failed_rounds=0
streak=0
longest=0
round=0

while [ "$round" -lt "$rounds" ]; do
  round=$((round + 1))
  now=$(date -u +%H:%M:%S)
  bad=0
  for url in https://apt.llvm.org/llvm.sh https://apt.llvm.org/trixie/ https://apt.llvm.org/llvm-snapshot.gpg.key; do
    if out=$(curl --silent --show-error --output /dev/null --connect-timeout 15 --max-time 60 \
      --write-out '%{http_code} %{remote_ip} %{time_connect}s' "$url" 2>&1); then
      :
    else
      bad=1
      echo "reach: $now round $round curl FAILED $url: $out"
    fi
  done
  # The same call as check_url() in llvm.sh.
  if wget -q --method=HEAD --timeout=15 --tries=3 https://apt.llvm.org/trixie/ > /dev/null 2>&1; then
    :
  else
    status=$?
    bad=1
    echo "reach: $now round $round wget HEAD FAILED exit=$status: $(wget --method=HEAD --timeout=15 --tries=1 https://apt.llvm.org/trixie/ 2>&1 | tail -n 3 | tr '\n' ' ')"
  fi
  if [ "$bad" -eq 1 ]; then
    failed_rounds=$((failed_rounds + 1))
    streak=$((streak + 1))
    [ "$streak" -gt "$longest" ] && longest=$streak
  else
    streak=0
  fi
  [ $((round % 15)) -eq 0 ] && echo "reach: $now round $round of $rounds, failed rounds so far $failed_rounds, longest streak $longest"
  sleep "$pause"
done

echo "reach: RESULT rounds=$rounds pause=${pause}s failed_rounds=$failed_rounds longest_streak=$longest (a streak of N covers about N x ${pause}s)"
exit 0
