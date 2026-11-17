"""Publish a workload cluster's API server on the LXD host.

Runs as the chart's post-install/post-upgrade hook. Four gates, each with its
own deadline: CAPN created the load-balancer instance; Cluster API wrote the
kubeconfig Secret; the instance runs and carries the `api-proxy` device; the API
server answers /livez through the load balancer. Every connection verifies its
peer: LXD against the server certificate in the CAPN identity Secret, the
management API against the service-account CA, the workload API against the CA
in the kubeconfig Secret.
"""

import base64
import json
import os
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request

IDENTITY = "/etc/capn-identity"
ACCOUNT = "/var/run/secrets/kubernetes.io/serviceaccount"
CLUSTER = os.environ["CLUSTER_NAME"]
NAMESPACE = os.environ["CLUSTER_NAMESPACE"]
SECRET = os.environ["KUBECONFIG_SECRET"]
DEVICE = {"type": "proxy", "listen": os.environ["PROXY_LISTEN"], "connect": "tcp:127.0.0.1:6443", "bind": "host"}


class NotYet(Exception):
    """The condition of a gate does not hold yet."""


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read().strip()


def lxd_tls():
    # LXD's certificate names the host, not the listener address. It is pinned
    # as LXD's own client does: the only trust anchor, no name check.
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_flags = ssl.VERIFY_X509_PARTIAL_CHAIN
    context.load_verify_locations(cadata=read(f"{IDENTITY}/server-crt"))
    context.load_cert_chain(f"{IDENTITY}/client-crt", f"{IDENTITY}/client-key")
    return context


LXD, PROJECT, LXD_TLS = read(f"{IDENTITY}/server"), read(f"{IDENTITY}/project"), lxd_tls()
KUBE_TLS = ssl.create_default_context(cafile=f"{ACCOUNT}/ca.crt")
TOKEN = read(f"{ACCOUNT}/token")


def call(url, context, method="GET", body=None, headers=None):
    request = urllib.request.Request(url, method=method, headers=headers or {})
    if body is not None:
        request.data = json.dumps(body).encode()
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, context=context, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # LXD and Kubernetes say why in the body ({"error": …} / {"message": …}).
        try:
            detail = json.loads(error.read() or b"{}")
        except ValueError:
            detail = {}
        reason = detail.get("error") or detail.get("message") or error.reason
        raise OSError(f"HTTP {error.code} from {method} {url.split('?')[0]}: {reason}") from None


def lxd(path, method="GET", body=None):
    separator = "&" if "?" in path else "?"
    return call(f"{LXD}{path}{separator}project={PROJECT}", LXD_TLS, method, body)["metadata"]


def gate(title, seconds, check):
    """Retry `check` until it returns a value; exit after `seconds`."""
    print(f"==> {title} (up to {seconds}s)", flush=True)
    deadline, last = time.monotonic() + seconds, "no answer"
    while time.monotonic() < deadline:
        try:
            return check()
        except (OSError, ValueError, KeyError, IndexError, TypeError, NotYet) as error:
            last = f"{type(error).__name__}: {error}"
        time.sleep(5)
    sys.exit(f"FAIL: {title}: not within {seconds}s; last: {last}")


def load_balancer():
    # CAPN marks its load balancer with these properties; the name is not matched.
    names = [
        instance["name"]
        for instance in lxd("/1.0/instances?recursion=1")
        if instance["config"].get("user.cluster-name") == CLUSTER
        and instance["config"].get("user.cluster-namespace") == NAMESPACE
        and instance["config"].get("user.cluster-role") == "loadbalancer"
    ]
    if len(names) > 1:
        sys.exit(f"FAIL: several load balancers of {NAMESPACE}/{CLUSTER}: {names}")
    if not names:
        raise NotYet("no instance yet")
    return names[0]


def workload_ca():
    url = f"https://kubernetes.default.svc/api/v1/namespaces/{NAMESPACE}/secrets/{SECRET}"
    secret = call(url, KUBE_TLS, headers={"Authorization": f"Bearer {TOKEN}"})
    kubeconfig = base64.b64decode(secret["data"]["value"]).decode()
    found = re.search(r"certificate-authority-data:\s*(\S+)", kubeconfig)
    if not found:
        sys.exit(f"FAIL: Secret {SECRET} holds no certificate-authority-data")
    return base64.b64decode(found.group(1)).decode()


def proxy(name):
    state = lxd(f"/1.0/instances/{name}/state")
    if state["status"] != "Running":
        raise NotYet(f"instance {name} is {state['status']}")
    if lxd(f"/1.0/instances/{name}")["devices"].get("api-proxy") != DEVICE:
        print(f"    adding api-proxy to {name}: {DEVICE['listen']} -> {DEVICE['connect']}", flush=True)
        lxd(f"/1.0/instances/{name}", "PATCH", {"devices": {"api-proxy": DEVICE}})
    for address in state["network"]["eth0"]["addresses"]:
        if address["family"] == "inet" and address["scope"] == "global":
            return address["address"]
    raise NotYet(f"instance {name} has no IPv4 address on eth0 yet")


def livez(address, ca):
    # The API server certificate names kubernetes.default.svc, whatever address leads to it.
    context = ssl.create_default_context(cadata=ca)
    with socket.create_connection((address, 6443), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname="kubernetes.default.svc") as tls:
            tls.sendall(b"GET /livez HTTP/1.1\r\nHost: kubernetes.default.svc\r\nConnection: close\r\n\r\n")
            status = tls.recv(64).split(b" ")[1]
    if status not in (b"200", b"401", b"403"):
        raise NotYet(f"/livez answered {status.decode()}")
    return status.decode()


def main():
    timeouts = {k: int(os.environ[f"TIMEOUT_{k.upper()}"]) for k in ("loadbalancer", "kubeconfig", "proxy", "livez")}
    name = gate("[1/4] the load-balancer instance", timeouts["loadbalancer"], load_balancer)
    print(f"    {name}", flush=True)
    ca = gate(f"[2/4] Secret {NAMESPACE}/{SECRET}", timeouts["kubeconfig"], workload_ca)
    address = gate(f"[3/4] {name} running with api-proxy", timeouts["proxy"], lambda: proxy(name))
    status = gate(f"[4/4] /livez through https://{address}:6443", timeouts["livez"], lambda: livez(address, ca))
    print(f"==> done: /livez {status}; the API is published on {DEVICE['listen']}", flush=True)


if __name__ == "__main__":
    main()
