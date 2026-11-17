{{/*
Name of a template object: <cluster>-<kind>-<8 hex of the sha256 of its spec>.
Templates are immutable once a Cluster uses them; a changed spec is a new
object, an unchanged spec keeps its name. Argument: (list $ "<kind>"), where
"capi-cluster-class.spec.<kind>" renders the spec.
*/}}
{{- define "capi-cluster-class.templateName" -}}
{{- $root := index . 0 -}}
{{- $kind := index . 1 -}}
{{- $spec := include (printf "capi-cluster-class.spec.%s" $kind) $root -}}
{{- printf "%s-%s-%s" $root.Values.cluster.name $kind (sha256sum $spec | trunc 8) -}}
{{- end -}}

{{/* Metadata of every object; `$kind` selects the spec. */}}
{{- define "capi-cluster-class.metadata" -}}
{{- $root := index . 0 -}}
name: {{ include "capi-cluster-class.templateName" . }}
namespace: {{ $root.Release.Namespace }}
labels:
  helm.sh/chart: {{ printf "%s-%s" $root.Chart.Name $root.Chart.Version }}
  app.kubernetes.io/name: {{ $root.Chart.Name }}
  app.kubernetes.io/instance: {{ $root.Release.Name }}
  app.kubernetes.io/managed-by: {{ $root.Release.Service }}
  app.kubernetes.io/part-of: cluster-api
{{- end -}}

{{/*
kubelet flags every node needs, then the extras (argument: the extras list).
Unprivileged containers cannot open /dev/kmsg; KubeletInUserNamespace lets the
kubelet start anyway. The node addresses come from /etc/sysconfig/kubelet
(capi-cluster-class.nodeCommands).
*/}}
{{- define "capi-cluster-class.kubeletArgs" -}}
- name: feature-gates
  value: KubeletInUserNamespace=true
- name: provider-id
  value: "lxc:///{{ "{{" }} v1.local_hostname {{ "}}" }}"
{{- with . }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Files every node needs. eth1 is the external network. systemd-networkd takes
its router advertisements and puts the routes they bring into their own table
(4200: outside Calico's route-table range 1-250 and the kernel's 253-255), so
the main table keeps one default route, via eth0, plus the external prefix
on-link through eth1. Connections that arrive on
eth1 are marked (bit 0x100: kube-proxy uses 0x4000 and 0x8000, Calico
0xffff0000), their replies take the mark, and the mark selects that table: what
arrives on eth1 is answered through eth1, everything else leaves through eth0. A
rule on the source address cannot do this: a reply to a VIP is forwarded Pod
traffic, whose source becomes the VIP only after routing.

The marks live in this node's own network namespace, in two chains of its own
in `ip6 mangle` (the image has ip6tables-nft, no nft), loaded in one
transaction before the kubelet starts. The host's firewall never sees them. The
kubelet requires them: a node that cannot load them does not join, and its
journal says why.

systemd-networkd keeps the routing rules other components add (Calico's
WireGuard or egress gateway would): by default it deletes every rule it was not
told about.
*/}}
{{- define "capi-cluster-class.nodeFiles" -}}
- path: /etc/systemd/networkd.conf.d/50-k8s-lab.conf
  owner: root:root
  permissions: "0644"
  content: |
    [Network]
    ManageForeignRoutingPolicyRules=no
- path: /etc/systemd/network/30-capi-ext.network
  owner: root:root
  permissions: "0644"
  content: |
    [Match]
    Name=eth1

    [Network]
    DHCP=no
    LinkLocalAddressing=ipv6
    IPv6AcceptRA=yes

    [IPv6AcceptRA]
    RouteTable=4200

    # The external segment itself stays on-link in the main table: neighbours on
    # it (other clusters' VIPs, other hosts) are reached directly, not through
    # the internal network and the host.
    [Route]
    Destination={{ .Values.externalNetwork.ipv6Prefix }}

    [RoutingPolicyRule]
    Family=ipv6
    FirewallMark=0x100/0x100
    Table=4200
    Priority=1000
- path: /etc/k8s-lab/ext-reply.rules
  owner: root:root
  permissions: "0644"
  content: |
    *mangle
    :K8S-LAB-EXT-REPLY - [0:0]
    -A K8S-LAB-EXT-REPLY -i eth1 -j CONNMARK --set-xmark 0x100/0x100
    -A K8S-LAB-EXT-REPLY ! -i eth1 -m connmark --mark 0x100/0x100 -j MARK --set-xmark 0x100/0x100
    :K8S-LAB-EXT-REPLY-OUT - [0:0]
    -A K8S-LAB-EXT-REPLY-OUT -m connmark --mark 0x100/0x100 -j MARK --set-xmark 0x100/0x100
    -A PREROUTING -j K8S-LAB-EXT-REPLY
    -A OUTPUT -j K8S-LAB-EXT-REPLY-OUT
    COMMIT
- path: /usr/local/sbin/k8s-lab-ext-reply
  owner: root:root
  permissions: "0755"
  content: |
    #!/bin/sh
    # Loads the eth1 reply marks (k8s-lab-ext-reply.service); says why it cannot.
    set -u
    if ! command -v ip6tables-nft-restore >/dev/null; then
      echo "k8s-lab: this node image has no ip6tables-nft-restore, which the eth1 reply marks need" >&2
      exit 1
    fi
    # A restart must not add the jumps twice; the restore re-creates both chains
    # empty and fills them. On a fresh boot there are none to remove.
    ip6tables-nft -t mangle -D PREROUTING -j K8S-LAB-EXT-REPLY 2>/dev/null
    ip6tables-nft -t mangle -D OUTPUT -j K8S-LAB-EXT-REPLY-OUT 2>/dev/null
    if ! ip6tables-nft-restore --noflush /etc/k8s-lab/ext-reply.rules; then
      echo "k8s-lab: loading the eth1 reply marks failed; the host must load the kernel modules nft_compat, xt_connmark and xt_mark (role host does)" >&2
      exit 1
    fi
- path: /etc/systemd/system/k8s-lab-ext-reply.service
  owner: root:root
  permissions: "0644"
  content: |
    [Unit]
    Description=k8s-lab: answer through eth1 what arrives on it
    Before=kubelet.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=/usr/local/sbin/k8s-lab-ext-reply

    [Install]
    WantedBy=multi-user.target
- path: /etc/systemd/system/kubelet.service.d/20-k8s-lab-ext-reply.conf
  owner: root:root
  permissions: "0644"
  content: |
    [Unit]
    Requires=k8s-lab-ext-reply.service
    After=k8s-lab-ext-reply.service
{{- end -}}

{{/*
Commands every node runs before kubeadm, then the extras (argument: the extras
list): restart systemd-networkd (it reads networkd.conf only when it starts; the
eth0 lease and the eth1 addresses come back within seconds, and the address
loop below waits for them), load the reply marks (the unit also runs at every
boot, before the kubelet), then give the kubelet both global eth0 addresses,
IPv4 first. LXD hands them out at boot, so they are read here; the kubelet unit
of the CAPN image reads KUBELET_EXTRA_ARGS from /etc/sysconfig/kubelet.
*/}}
{{- define "capi-cluster-class.nodeCommands" -}}
- systemctl restart systemd-networkd
- systemctl daemon-reload
- systemctl enable --now k8s-lab-ext-reply.service
- |
  set -eu
  for _ in $(seq 1 120); do
    v4=$(ip -o -4 addr show dev eth0 scope global | awk '{split($4,a,"/"); print a[1]; exit}')
    v6=$(ip -o -6 addr show dev eth0 scope global | awk '$0 !~ /(temporary|deprecated|tentative)/ {split($4,a,"/"); print a[1]; exit}')
    if [ -n "$v4" ] && [ -n "$v6" ]; then break; fi
    sleep 1
  done
  test -n "$v4"
  test -n "$v6"
  mkdir -p /etc/sysconfig
  printf 'KUBELET_EXTRA_ARGS=--node-ip=%s,%s\n' "$v4" "$v6" > /etc/sysconfig/kubelet
{{- with . }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* The LXD image of a machine class (argument: its image value). */}}
{{- define "capi-cluster-class.image" -}}
name: {{ .ref | quote }}
{{- with .fingerprint }}
fingerprint: {{ . | quote }}
{{- end }}
{{- end -}}
