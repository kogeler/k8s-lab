# k8s-lab

Kubernetes clusters on one Debian or Ubuntu host, managed by Cluster API:
unprivileged LXC system containers as nodes, a self-hosted management cluster,
workload clusters through Terraform. This site documents the repository's
roles, charts and modules and how to run them.

| To | Read |
|---|---|
| understand how it fits together | [Architecture](architecture.md) |
| try it on a local VM | [Quickstart](quickstart-local.md) |
| run it on a host | [Deploy](deploy.md), [variable contract](variable-contract.md) |
| operate it: upgrade, scale, rotate, back up, reboot, tear down | [Runbooks](runbooks/README.md) |
| fix something | [Troubleshooting](troubleshooting.md) |
| know why it is built this way | [Decisions](decisions/README.md) |
| look up an input, a value or a version | [Roles](reference/roles.md), [Terraform modules](reference/terraform.md), [Charts](reference/charts.md), [Versions](reference/versions.md) |
| change it | [Development](development.md) |
| see what changed | [Changelog](changelog.md) |

Source: <https://github.com/kogeler/k8s-lab>.
