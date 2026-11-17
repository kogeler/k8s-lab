#!/bin/sh
# Gate A client: the gate's LoadBalancer Service gets an address from the pool
# (read from its status through the API: MetalLB chooses it), and that address
# answers from the gate's own server. Environment: NAMESPACE, SERVICE, PORT,
# TIMEOUT (seconds).
set -eu
sa=/var/run/secrets/kubernetes.io/serviceaccount
api="https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE/services/$SERVICE"
deadline=$(($(date +%s) + TIMEOUT))
address="" last="no address assigned yet"
while [ "$(date +%s)" -lt "$deadline" ]; do
  if [ -z "$address" ]; then
    # The first ingress address; the API server's JSON, spaces removed.
    address=$(curl -fsS --max-time 5 --cacert "$sa/ca.crt" -H "Authorization: Bearer $(cat "$sa/token")" "$api" \
      | tr -d ' \n\t' | sed -n 's/.*"ingress":\[{"ip":"\([0-9a-fA-F:.]*\)".*/\1/p' || true)
  fi
  if [ -n "$address" ]; then
    url="http://[$address]:$PORT/hostname"
    if answer=$(curl -fsS --max-time 3 "$url"); then
      case $answer in
        "$SERVICE"-*) echo "Gate A: $SERVICE got $address; $url answered from $answer"; exit 0 ;;
      esac
      last="$url answered from $answer, not from the gate's server"
    else
      last="no answer from $url"
    fi
  fi
  sleep 3
done
echo "FAIL: Gate A: not within ${TIMEOUT}s; last: $last" >&2
exit 1
