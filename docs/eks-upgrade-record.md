# WordPress lab EKS upgrade record

Recorded 2026-10-30 for the completed **1.34 -> 1.35 -> 1.36** upgrade.
Commands appear once in the [reusable process](eks-upgrade-process.md).
Each historical stage links its procedure and validation, without repeating them.

The operator reported completion, reflected in local Terraform state. Raw outputs
for every intermediate check were not archived. This record does not assert the
cluster still exists: a later cost-saving teardown was requested separately.

## Environment

| Setting | Recorded value |
| --- | --- |
| Profile / Region | `lab-admin` / `ap-south-1` |
| Cluster / node group | `wp-lab-eks` / `wp-lab-workers` |
| Context / workspace / branch | `wp-lab` / `default` / `develop` |
| Compute | AL2023 x86_64 standard, On-Demand `t3.medium`, two AZs |
| Scaling / update budget | min 2, desired 2, max 3; `max_unavailable = 1` |
| Application | One WordPress Deployment, one MariaDB StatefulSet, AZ-bound RWO gp3 disks |
| Access/deployment | Localhost port-forward; local Helm render plus kubectl apply; no application ALB/Ingress or Helm release history |
| Backup exception | Database backup/write freezing waived for this disposable lab; no restore drill recorded |

Use the [backup gate](eks-upgrade-process.md#backup-gate) for future valuable data.
Retained disks were not treated as backups.

## Preparation shared by both hops

Preparation separated control-plane, worker, AMI release and managed add-on
version targets in [variables.tf](../variables.tf), [eks.tf](../eks.tf),
[nodes.tf](../nodes.tf), and [addons.tf](../addons.tf). Explicit pins replaced
latest-version lookups and matched running AWS packages. The operator confirmed
a no-change baseline plan. This prevented one edit from silently combining stages.

Reuse [context/baseline](eks-upgrade-process.md#context) and
[plan review](eks-upgrade-process.md#plan-apply) for future upgrades.

## Hop 1: 1.34 to 1.35

| Stage | Recorded values/evidence | Shared procedure | Validation commands |
| --- | --- | --- | --- |
| Readiness | Operator reported target insights PASSING and prerequisite pins suitable | [Readiness](eks-upgrade-process.md#readiness) | [Insights](eks-upgrade-process.md#insights), [compatibility](eks-upgrade-process.md#compatibility), [capacity](eks-upgrade-process.md#capacity) |
| Control plane | 1.34 -> 1.35; observed server `v1.35.9-eks-577a51e`; workers initially remained 1.34 | [Control plane](eks-upgrade-process.md#control-plane) | [Cluster](eks-upgrade-process.md#v-cluster) |
| Workers | `1.34.12-20261026` -> `1.35.9-20261026`; supplied output showed two Ready 1.35 nodes and ACTIVE node group, health `[]` | [Workers](eks-upgrade-process.md#workers) | [Workers](eks-upgrade-process.md#v-workers), [workloads](eks-upgrade-process.md#v-workloads) |
| kube-proxy | `v1.34.6-eksbuild.62` -> `v1.35.3-eksbuild.59`; operator reported apply complete | [Add-on](eks-upgrade-process.md#addons) | [Add-on health](eks-upgrade-process.md#v-addon) |
| Closure | Application/system pods shown Ready after node replacement; end-to-end testing is an operator-recorded check | [Closure](eks-upgrade-process.md#closure) | [Application/storage](eks-upgrade-process.md#v-workloads), [Terraform](eks-upgrade-process.md#v-terraform) |

## Hop 2: 1.35 to 1.36

| Stage | Recorded values/evidence | Shared procedure | Validation commands |
| --- | --- | --- | --- |
| Readiness | Operator reported 1.36 insights PASSING; API output confirmed four infrastructure pins support 1.36/amd64/ec2 | [Readiness](eks-upgrade-process.md#readiness) | [Insights](eks-upgrade-process.md#insights), [compatibility](eks-upgrade-process.md#compatibility), [capacity](eks-upgrade-process.md#capacity) |
| Control plane | Reviewed plan changed only `aws_eks_cluster.main.version`; operator confirmed 1.36 ACTIVE | [Control plane](eks-upgrade-process.md#control-plane) | [Cluster](eks-upgrade-process.md#v-cluster) |
| Workers | `1.35.9-20261026` -> `1.36.5-20261026`; completion reported; local state recorded version 1.36/ACTIVE | [Workers](eks-upgrade-process.md#workers) | [Workers](eks-upgrade-process.md#v-workers), [workloads](eks-upgrade-process.md#v-workloads) |
| kube-proxy | `v1.35.3-eksbuild.59` -> `v1.36.0-eksbuild.58`; final package in local state | [Add-on](eks-upgrade-process.md#addons) | [Add-on health](eks-upgrade-process.md#v-addon) |
| Helm alignment | Renderers/README target changed to 1.36.0; PowerShell 5.1 rendering and WordPress lint passed; ESO archive hash verified | [Helm review](eks-upgrade-process.md#helm-applications) | [Local render](../README.md#4-render-locally), [live checks](eks-upgrade-process.md#v-workloads) |
| Closure | Operator reported workers/nodes/add-ons completed; future runs should archive fresh health and no-change-plan evidence | [Closure](eks-upgrade-process.md#closure) | [Closing checks](eks-upgrade-process.md#closure) |

## Recorded final pins

Historical values only: re-query regional compatibility and AMI metadata for a
future target instead of copying these pins.

| Component | Pin |
| --- | --- |
| Control plane / workers | `1.36` / `1.36` |
| AL2023 worker AMI release | `1.36.5-20261026` |
| kube-proxy | `v1.36.0-eksbuild.58` |
| VPC CNI | `v1.23.2-eksbuild.8` |
| CoreDNS | `v1.13.2-eksbuild.62` |
| EBS CSI | `v1.67.2-eksbuild.1` |
| Pod Identity Agent | `v1.4.1-eksbuild.3` |

CNI/CoreDNS returned `defaultVersion: false` for 1.36 but their exact pins were
compatible. EBS CSI and Pod Identity Agent were default builds. Compatibility,
rather than default selection, determined whether prerequisite updates were needed.

## Lessons recorded

- An ISP public-IP change caused API timeouts; allowlist repair was a separate
  access change, not a Kubernetes-version change.
- An add-on plan accidentally included the next control-plane version. Correcting
  the desired default and regenerating the saved plan kept stages separate.
- Many watch rows represented the same node. Temporary new workers were part of
  managed replacement, and the final normal count returned to two.
- Standard On-Demand quota was 16 vCPUs; possible six-node `t3.medium` surge used
  12. Autoscaling does not bypass the quota.
- Node budgets and pod PDBs are distinct; singleton workloads/RWO AZ-bound disks
  still permit interruption.
- Add-on packages, node AMI releases, Helm chart versions and application image
  versions describe different components and need not match.

<a id="future-record-template"></a>
## Future record template

Create a new record for the environment. Link the shared process and validations;
do not copy command bodies per hop or pre-populate successful results.

| Field | Actual result/evidence |
| --- | --- |
| Date/operator/change reference | |
| Account/profile/Region/context/workspace | |
| Cluster/node groups and source -> target minor | |
| Starting versions and no-drift baseline | |
| Insight refresh time/statuses/resolutions | |
| Compatibility, quota/headroom and subnet/AZ evidence | |
| Backup/recovery-point/restore-test evidence or disposable-lab waiver | |
| Control-plane plan, old/new values, apply and [validation](eks-upgrade-process.md#v-cluster) | |
| Worker plan, old/new AMI, apply and [validation](eks-upgrade-process.md#v-workers) | |
| Each add-on plan, old/new package, apply and [validation](eks-upgrade-process.md#v-addon) | |
| [Application/data/ESO checks](eks-upgrade-process.md#v-workloads), interruption/observation period | |
| [No-change plan](eks-upgrade-process.md#v-terraform) and open exceptions | |
| Recovery decision and [procedure](eks-upgrade-process.md#recovery), if needed | |
