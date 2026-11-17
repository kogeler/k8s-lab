#!/bin/sh
# Gate B client: every endpoint of the headless Service answers over IPv4 and
# over IPv6, and the answers come from REPLICAS different servers (one per
# worker). Environment: SERVICE, REPLICAS, PORT, TIMEOUT (seconds).
set -eu
deadline=$(($(date +%s) + TIMEOUT))
last="no DNS answer yet"
while [ "$(date +%s)" -lt "$deadline" ]; do
  # A failed lookup (no answer from the cluster DNS yet) is retried: under
  # `set -e` it would end the script without a word. dig prints its error on
  # stdout, so it ends up in `last`.
  v4=$(dig +short +search "$SERVICE" A || true)
  v6=$(dig +short +search "$SERVICE" AAAA || true)
  if [ "$(printf '%s\n' "$v4" | grep -c .)" -eq "$REPLICAS" ] && [ "$(printf '%s\n' "$v6" | grep -c .)" -eq "$REPLICAS" ]; then
    answers="" failed=""
    for address in $v4 $v6; do
      case $address in
        *:*) url="http://[$address]:$PORT/hostname" ;;
        *) url="http://$address:$PORT/hostname" ;;
      esac
      if answer=$(curl -fsS --max-time 3 "$url"); then
        answers="$answers$answer
"
      else
        failed="$url"
        break
      fi
    done
    servers=$(printf '%s' "$answers" | sort -u | grep -c . || true)
    if [ -z "$failed" ] && [ "$servers" -eq "$REPLICAS" ]; then
      printf 'Gate B: %s over IPv4 (%s) and IPv6 (%s), from:\n%s' "$SERVICE" "$(echo "$v4" | tr '\n' ' ')" "$(echo "$v6" | tr '\n' ' ')" "$answers"
      exit 0
    fi
    last="no answer from ${failed:-every server}; servers seen: $servers"
  else
    last="DNS: A $(echo "$v4" | tr '\n' ' ') AAAA $(echo "$v6" | tr '\n' ' ')"
  fi
  sleep 5
done
echo "FAIL: Gate B: not within ${TIMEOUT}s; last: $last" >&2
exit 1
