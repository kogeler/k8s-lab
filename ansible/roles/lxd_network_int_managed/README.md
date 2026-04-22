# lxd_network_int_managed

Create and configure LXD managed bridge networks for the k8s-lab
internal plane (plan §13.5).

## Purpose

Owns LXD-managed bridge network objects. The bridges live in the
**default** LXD project because LXD rejects `bridge` type networks in
non-default projects ("Network type does not support non-default
projects"). The `capi-lab` project references these networks read-only
through its `features.networks=false` inheritance (owned by
`lxd_project`).

Out of scope:

* Host-level Linux bridges — owned by `lxd_host` (external bridge
  `br-ext6`).
* Non-bridge network types (OVN, physical, macvlan) — not modelled.
* Profiles' nic device references — owned by `lxd_profiles`.

Implemented through `ansible.builtin.uri` over the LXD snap unix
socket. `community.general` ships no CREATE module for networks;
`uri` + REST is the native-first path (plan §2.6.1).

## Requirements

* Target host runs **Debian 13 Trixie** or newer.
* `lxd_project` has already run (sets `features.networks=false` on
  `capi-lab` so inheritance resolves). Declared as a meta dependency
  so callers get the chain automatically (plan §2.6.5).
* `ansible.builtin.uri` (built in — no extra collection).

## Role variables

All public variables use the `lxd_network_int_managed_*` prefix
(plan §2.6.2).

### General

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_network_int_managed_lxd_socket_path` | `/var/snap/lxd/common/lxd/unix.socket` | Path to the LXD unix socket. |

### Networks

`lxd_network_int_managed_networks` is a list of network definitions.
Each entry:

| Field | Required | Description |
| --- | --- | --- |
| `name` | yes | Network name. ≤15 chars (Linux IFNAMSIZ). |
| `type` | no (default `bridge`) | Only `bridge` is supported by this role's scope. |
| `description` | no | Stored on the network. |
| `config` | yes | LXD network config dict; string values. Must set at least one of `ipv4.address` / `ipv6.address`. Put tunable keys (addresses, MTU, hwaddr) here — the substrate-required NAT/DHCP keys are baked into the role. |

**Substrate-required baseline (role-internal, not user-overridable):**
the NAT and DHCP keys every k8s-lab managed bridge must carry live in
`vars/main.yml` as `_lxd_network_int_managed_required_config`:

```yaml
ipv4.nat:  "true"
ipv4.dhcp: "true"
ipv6.nat:  "true"
ipv6.dhcp: "true"
```

These are merged on top of each entry's user-supplied `config` at apply
time — **required keys always win the combine**, so an override in
`lxd_network_int_managed_networks` cannot silently disable NAT or DHCP.
(Plan §4.1 puts the internal plane behind host NAT; plan §5.2 requires
DHCP/RA for every capi-lab node's internal nic.)

Default list (plan §8 addresses, NAT/DHCP supplied by the baseline):

```yaml
lxd_network_int_managed_networks:
  - name:        "capi-int"
    type:        "bridge"
    description: "k8s-lab internal managed bridge (dual-stack, NAT, DHCPv4, RAv6)"
    config:
      ipv4.address: "10.77.0.1/24"
      ipv6.address: "fd42:77:1::1/64"
```

### Flow control

| Variable | Default | Description |
| --- | --- | --- |
| `lxd_network_int_managed_enabled` | `true` | Whole-role toggle. |
| `lxd_network_int_managed_flow_control_networks` | `true` | Skip the create / patch section. |

## Tags

Both `_` and `-` spellings are accepted (plan §2.6.3):

* `lxd_network_int_managed` / `lxd-network-int-managed` — whole role.
* `lxd_network_int_managed_preflight` — input validation only.
* `lxd_network_int_managed_networks` — create / patch.
* `lxd_network_int_managed_healthchecks` — in-role healthchecks.

## Example

```yaml
- hosts: k8slab_host
  become: true
  roles:
    - role: lxd_network_int_managed
      vars:
        lxd_network_int_managed_networks:
          - name:        "capi-int"
            description: "lab internal managed bridge"
            # Only the address keys are tunable here. The required
            # NAT + DHCP keys are merged on top automatically.
            config:
              ipv4.address: "10.77.0.1/24"
              ipv6.address: "fd42:77:1::1/64"
```

## Testing

Ships a Molecule delegated-driver scenario under
`tests/molecule/lxd-network-int-managed/` that:

* converges the role on the shared Vagrant VM (pulls `lxd_project` /
  `lxd_host` / `base_system` in transitively through meta deps);
* asserts idempotence;
* runs verify reading live state from LXD's REST API and checking type
  / managed / status / every declared config key lands unchanged.

Run locally:

```bash
make -C tests/molecule lxd-network-int-managed-delegated-test
```

## Caveats

* **Bridges live in the default project, not in `capi-lab`.** LXD
  does not support `bridge` type networks in non-default projects.
  capi-lab references them through `features.networks=false`
  inheritance; see `lxd_project` docs.
* **Network name doubles as a host interface name.** Linux caps
  interface names at 15 chars (IFNAMSIZ) — preflight enforces the
  limit.
* **LXD always emits IPv6 RAs when `ipv6.address` is set.** A separate
  `ipv6.ra` key does not exist; the only way to suppress RAs is to
  not set an IPv6 address.
