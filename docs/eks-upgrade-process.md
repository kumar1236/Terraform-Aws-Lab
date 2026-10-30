# EKS upgrade process

This is the reusable procedure for **one minor-version hop** in an existing
Terraform-managed EKS cluster. Complete N to N+1 before starting the next hop.
The [lab upgrade record](eks-upgrade-record.md) links both historical upgrades
to this procedure instead of copying its commands.

Run these native PowerShell/AWS CLI/Terraform/kubectl commands manually, one at a
time, from the repository root. This document does not execute an upgrade. It
covers conventional EC2 managed node groups, not EKS Auto Mode. Other clusters
need their own context and change record. Cross-region DNS/database failover
requires a separate operational plan. After lab destruction, redeployment is a
separate workflow in the [README](../README.md).

The sequence is readiness -> control plane -> workers -> add-ons -> application
validation -> Terraform closure. See the [AWS upgrade sequence](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html).

## Navigation

| Action | Shared procedure | Validation commands |
| --- | --- | --- |
| Establish baseline | [1. Context](#context) | [Cluster](#v-cluster), [workers](#v-workers), [workloads](#v-workloads) |
| Prepare next minor | [2. Readiness](#readiness), [backup gate](#backup-gate) | [Insights](#insights), [compatibility](#compatibility), [capacity](#capacity) |
| Change control plane | [3. Control plane](#control-plane) | [Cluster](#v-cluster) |
| Replace workers | [4. Workers](#workers) | [Workers](#v-workers) |
| Change one add-on | [5. Add-ons](#addons) | [Add-on](#v-addon) |
| Review Helm/application | [6. Application](#helm-applications) | [Workloads, ESO, storage](#v-workloads) |
| Close the hop | [7. Closure](#closure) | [Terraform](#v-terraform) |
| Plan/apply any stage | [Common plan/apply](#plan-apply) | Expected resource is specified by each stage |
| Investigate failure | [Recovery](#recovery) | [Diagnostics](#diagnostics) |

<a id="context"></a>
## 1. Confirm context and baseline

Set these for the environment and one hop. The example is the lab's second hop;
replace its versions for a future upgrade. An existing cluster/state is required.

```powershell
$upgradeAwsProfile = 'lab-admin'
$region = 'ap-south-1'
$clusterName = 'wp-lab-eks'
$nodeGroupName = 'wp-lab-workers'
$contextName = 'wp-lab'
$currentVersion = '1.35'
$targetVersion = '1.36'
$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$env:AWS_PROFILE = $upgradeAwsProfile
```

```powershell
aws sts get-caller-identity --profile $upgradeAwsProfile --region $region
terraform workspace show
terraform state list
aws eks update-kubeconfig --name $clusterName --alias $contextName --profile $upgradeAwsProfile --region $region
kubectl config current-context
kubectl version
```

Lab expectations: account `115278085846`, workspace `default`, context `wp-lab`,
branch `develop`. Record another environment's actual identity instead of
accepting these defaults. Keep kubectl within supported version skew.

Initialize these variables in each new terminal used for AWS monitoring; they
are not inherited by a new PowerShell session. Keep plan/apply commands in the
original terminal where the stage's plan filename was set, or explicitly restore
that filename before using it.

Run shared [cluster](#v-cluster), [worker](#v-workers), [workload](#v-workloads),
and [Terraform](#v-terraform) checks. Use [add-on validation](#v-addon) for each
installed add-on below. Record starting versions/health and resolve unexpected
drift or unhealthy components before changing a version.

| AWS add-on | Terraform resource | Key in `eks_addon_versions` | Kubernetes workload |
| --- | --- | --- | --- |
| `vpc-cni` | `aws_eks_addon.vpc_cni` | `vpc_cni` | DaemonSet `aws-node` |
| `kube-proxy` | `aws_eks_addon.kube_proxy` | `kube_proxy` | DaemonSet `kube-proxy` |
| `coredns` | `aws_eks_addon.coredns` | `coredns` | Deployment `coredns` |
| `aws-ebs-csi-driver` | `aws_eks_addon.ebs_csi` | `ebs_csi` | Deployment `ebs-csi-controller`, DaemonSet `ebs-csi-node` |
| `eks-pod-identity-agent` | `aws_eks_addon.pod_identity_agent` | `pod_identity_agent` | DaemonSet `eks-pod-identity-agent` |

Pins are in [variables.tf](../variables.tf); resource wiring is in
[eks.tf](../eks.tf), [nodes.tf](../nodes.tf), and [addons.tf](../addons.tf).
Keep control-plane, worker, AMI and add-on targets independent. Use EKS add-on
**package versions** from `describe-addon`, not container image tags. For example,
Pod Identity Agent's package and container can have different versions. Keep
provider and application-image changes separate from the Kubernetes upgrade.

<a id="readiness"></a>
## 2. Prepare the next minor-version hop

<a id="insights"></a>
### Refresh and review insights

```powershell
aws eks start-insights-refresh --cluster-name $clusterName --profile $upgradeAwsProfile --region $region
aws eks describe-insights-refresh --cluster-name $clusterName --profile $upgradeAwsProfile --region $region
```

Repeat the second command after a short wait while status is `IN_PROGRESS`.
Continue after `COMPLETED`; investigate `FAILED`.

```powershell
aws eks list-insights --cluster-name $clusterName --profile $upgradeAwsProfile --region $region --filter "categories=UPGRADE_READINESS,kubernetesVersions=$targetVersion" --query "insights[].{Name:name,Version:kubernetesVersion,Status:insightStatus.status,Reason:insightStatus.reason,ID:id,Refreshed:lastRefreshTime}" --output table
```

Expected: fresh target checks passing. Review `WARNING`, `ERROR`, `UNKNOWN`, or
an empty result; an empty list is not clearance. Do not filter only passing
results. Insights complement application/controller testing; they do not replace
it. Sources: [refresh statuses](https://docs.aws.amazon.com/cli/latest/reference/eks/describe-insights-refresh.html),
[insight filters](https://docs.aws.amazon.com/cli/latest/reference/eks/list-insights.html).

<a id="compatibility"></a>
### Check installed add-on and workload compatibility

Set one add-on's name and **actual installed pin**, then run this lookup. Reuse it
for the non-kube-proxy add-ons in the inventory by changing those two variables.
The example pin is historical, not a future target.

```powershell
$addonName = 'vpc-cni'
$pinnedAddonVersion = 'v1.23.2-eksbuild.8'
aws eks describe-addon-versions --addon-name $addonName --kubernetes-version $targetVersion --profile $upgradeAwsProfile --region $region --query "addons[0].addonVersions[?addonVersion=='$pinnedAddonVersion'].{Version:addonVersion,Architectures:architecture,ComputeTypes:computeTypes,Compatibility:compatibilities}" --output json
```

Expected for this group: exact pin, target `clusterVersion`, `amd64` and `ec2`.
Inspect platform restrictions; `platformVersions: ["*"]` covers all EKS platform
versions for that compatibility entry. `defaultVersion: false` means non-default,
not incompatible. Retain compatible pins. If a prerequisite update is needed,
select a build compatible with the **current and target** minors and use the
[add-on procedure](#addons) as a separate change before the control-plane stage.

Keep kube-proxy at the current minor during the control-plane transition, then
select its target-minor build in [the add-on stage](#addons). It must not be newer
than the API server. Sources: [AWS compatibility](https://docs.aws.amazon.com/eks/latest/userguide/addon-compat.html),
[Kubernetes version skew](https://kubernetes.io/releases/version-skew-policy/).

Review the target's [EKS release notes](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html),
API removals, webhooks, ESO support policy and customer-managed controllers.
The 1.36 review included containerd 2.0+, disabled `gitRepo` volumes, strict IP/CIDR
validation and SELinux volume rules. Observed lab nodes used AL2023/containerd
2.3.7; the custom chart did not use `gitRepo` or custom SELinux labels. Repeat the
review for future versions; existing healthy pods alone do not establish support.

<a id="capacity"></a>
### Check capacity, storage placement and disruption limits

```powershell
$clusterSubnetIds = aws eks describe-cluster --name $clusterName --profile $upgradeAwsProfile --region $region --query 'cluster.resourcesVpcConfig.subnetIds' --output json | ConvertFrom-Json
aws ec2 describe-subnets --subnet-ids $clusterSubnetIds --profile $upgradeAwsProfile --region $region --query 'Subnets[].{Subnet:SubnetId,AZ:AvailabilityZone,FreeIPs:AvailableIpAddressCount}' --output table
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A --profile $upgradeAwsProfile --region $region --query 'Quota.{Name:QuotaName,Limit:Value}' --output table
aws ec2 describe-instances --filters 'Name=instance-state-name,Values=pending,running' --profile $upgradeAwsProfile --region $region --query 'Reservations[].Instances[].{Instance:InstanceId,Type:InstanceType,Lifecycle:InstanceLifecycle,State:State.Name}' --output table
kubectl get pdb -A
```

The control plane needs available subnet IPs for replacement interfaces; new
workers/pods also need addresses. Check regional quota **remaining headroom**,
including other eligible On-Demand instances, not just the total limit. Recheck
capacity before workers if usage changed.

For two AZs and two `t3.medium` workers, DEFAULT updating can launch four extra
nodes: six total / 12 vCPUs temporarily. The lab's observed quota was 16 vCPUs
with only two workers running; this is historical, not reserved capacity. EKS
can temporarily raise the Auto Scaling group's maximum above Terraform's
`max_size = 3`. `max_unavailable = 1` limits unavailable **nodes**, not new-node
count. See [AWS update phases](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-update-behavior.html).

PDBs independently restrict voluntary **pod** evictions. The lab's CoreDNS and EBS
controller budgets each allowed one disruption. Investigate zero allowances for
workloads that must be drained. WordPress and MariaDB each have one replica and
RWO EBS storage: node replacement can interrupt service, and replacement capacity
is needed in the volumes' AZs. A singleton `minAvailable: 1` PDB blocks eviction
rather than adding availability. Autoscaling does not bypass quotas or provide
shared storage/database availability.

Complete the [backup and recovery gate](#backup-gate) before the first mutation.

<a id="control-plane"></a>
## 3. Upgrade only the control plane

Manually change only `eks_cluster_version` in [variables.tf](../variables.tf)
from the current to the target minor. Keep worker, AMI and add-on pins at their
reviewed values. Record the before/after values.

```powershell
$stagePlanFile = "eks-$targetVersion-control-plane-$runId.tfplan"
```

Use the [common plan/apply procedure](#plan-apply).
**Expected plan:** only `aws_eks_cluster.main.version`, current -> target;
`0 to add, 1 to change, 0 to destroy`.

Use [cluster validation](#v-cluster) periodically in another terminal. Wait for
Terraform success and `ACTIVE` at the target; version alone is insufficient.
Workers stay at the source minor. API/port-forward sessions may reconnect. If
apply fails, use [diagnostics](#diagnostics) before retrying or advancing stages.

<a id="workers"></a>
## 4. Upgrade managed workers

After the target control plane is healthy, retrieve a fresh regional AMI release
for the target minor and this group's AL2023 x86 standard image type:

```powershell
aws ssm get-parameter --name "/aws/service/eks/optimized-ami/$targetVersion/amazon-linux-2023/x86_64/standard/recommended/release_version" --profile $upgradeAwsProfile --region $region --query 'Parameter.Value' --output text
```

Record the returned release. Change **both** `eks_node_version` and
`eks_node_ami_release_version` in [variables.tf](../variables.tf). Do not guess a
release or reuse the previous minor's AMI pin. Retain the reviewed instance type,
scaling, storage, IAM and update settings.

```powershell
$stagePlanFile = "eks-$targetVersion-workers-$runId.tfplan"
```

Use the [common plan/apply procedure](#plan-apply).
**Expected plan:** only `aws_eks_node_group.main`, changing version and AMI
release; `0 to add, 1 to change, 0 to destroy`. The node-group resource is updated
in place, but underlying EC2 instances are replaced.

Start each monitor in a separate terminal:

```powershell
kubectl get nodes -o wide --watch
```

```powershell
kubectl get pods -A -o wide --watch
```

EKS creates replacements, waits for readiness, drains old nodes and removes them.
New nodes can briefly be `NotReady` while bootstrapping. Watch rows repeat the
same names; use the snapshot in [worker validation](#v-workers) for actual count.
Ctrl+C in a watch terminal stops monitoring, not AWS updating. Avoid interrupting
the separate Terraform apply terminal.

If a rollout stalls, inspect EKS health, PDBs, pod events, volume attachments,
AZ/IP capacity and quotas. Do not automatically force updates, delete PVCs or
force-detach disks. Complete [worker](#v-workers) and [workload](#v-workloads)
validation before changing add-on pins.

<a id="addons"></a>
## 5. Review/update one managed add-on at a time

EKS does not automatically update managed add-ons with cluster/node upgrades.
Retain pins already confirmed compatible in [readiness](#compatibility). For
kube-proxy, select a target-minor package after the control-plane upgrade:

```powershell
$addonName = 'kube-proxy'
aws eks describe-addon-versions --addon-name $addonName --kubernetes-version $targetVersion --profile $upgradeAwsProfile --region $region --query "addons[0].addonVersions[?compatibilities[?clusterVersion=='$targetVersion' && defaultVersion]].{Version:addonVersion,Architectures:architecture,ComputeTypes:computeTypes}" --output json
```

Check `amd64`/`ec2`, record the actual package, and change only its entry inside
`eks_addon_versions` in [variables.tf](../variables.tf). Its patch/build need not
match the worker patch. Investigate empty results instead of guessing a build.

```powershell
$stagePlanFile = "eks-$targetVersion-$addonName-$runId.tfplan"
```

Use the [common plan/apply procedure](#plan-apply).
**Expected plan:** only the mapped `aws_eks_addon` resource in the inventory;
`0 to add, 1 to change, 0 to destroy` for one package change. Finish with
[add-on](#v-addon) and [workload](#v-workloads) validation. For another package,
reuse this section with its explicit name/pin.

For a future worker strategy change, apply that configuration separately before
the version update. Do not assume the provider updates configuration before
version when both change in one apply. Sources: [AWS add-on updating](https://docs.aws.amazon.com/eks/latest/userguide/updating-an-add-on.html),
[locked provider implementation](https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/v6.70.0/internal/service/eks/node_group.go).

<a id="helm-applications"></a>
## 6. Align future Helm rendering and validate applications

Reuse the [local render procedure](../README.md#4-render-locally) and
[server validation procedure](../README.md#6-check-against-eks-then-apply-the-application).
Keep approved application/database image pins during the infrastructure change.
Rendering for a new Kubernetes version alone is not a reason to redeploy.

For future hops, align both renderers and README examples with the target minor
plus `.0`, such as `--kube-version 1.36.0`. This sets Helm's
`.Capabilities.KubeVersion`; it does not upgrade EKS or validate against its API.
Preserve the chart's `apiVersion: v2`, chart version and WordPress `appVersion`
unless those change independently. See [Helm template options](https://helm.sh/docs/helm/helm_template/).

Use [workload validation](#v-workloads). Test the home page, administrator login,
existing posts/media, and a disposable write/read followed by a pod restart where
appropriate. Record interruption and persistence results. Reconfirm ESO readiness
and synchronization after replacement pods start.

<a id="closure"></a>
## 7. Close the hop

Run [cluster](#v-cluster), [workers](#v-workers), every [add-on](#v-addon),
[workloads](#v-workloads), and [Terraform](#v-terraform) checks. Record real outputs,
timestamps and selected versions in the [change record](eks-upgrade-record.md#future-record-template).
Complete the environment's observation period before another minor hop. Then set
`currentVersion` to the completed target, choose the next target and a fresh run
ID, and return to [readiness](#readiness). Re-query version compatibility and AMIs.
Each forward hop changes the previous version available for eligible rollback.

<a id="plan-apply"></a>
## Common plan review and apply

Use this single procedure after the stage sets `$stagePlanFile` and identifies
its expected resource. Run from the repository root.

```powershell
terraform fmt variables.tf
terraform validate
terraform plan -out=$stagePlanFile
```

Check each command's exit status (`$LASTEXITCODE`) before moving on; require `0`.
If plan generation fails, stop: an older file at the same path can still exist.
For every regeneration, choose a fresh filename (refresh `$runId` and rerun the
stage's filename assignment) instead of risking an older saved plan.

After successful generation, inspect that exact file:

```powershell
terraform show -no-color $stagePlanFile
```

Review the **whole** plan, including outputs. Confirm only the expected resource
and fields change. A kube-proxy plan that also changes the control plane must be
corrected before applying. Inspect variable defaults, `*.tfvars`, automatic
variable files, `TF_VAR_*`, and CLI overrides for unexpected targets. Use a full
plan; do not hide changes with `-target`.

Saved plans retain their creation-time configuration/inputs. Editing a file does
not edit that binary plan: regenerate and review it. Use the fresh stage file,
not an older approved plan.

Only after the plan matches the intended stage, execute:

```powershell
terraform apply $stagePlanFile
```

Monitor using that stage's links. Terraform success and application health are
separate evidence. Never run overlapping applies. Source:
[Terraform plan](https://developer.hashicorp.com/terraform/cli/commands/plan).

## Validation commands (one shared reference)

<a id="v-cluster"></a>
### Cluster/control-plane validation

```powershell
aws eks describe-cluster --name $clusterName --profile $upgradeAwsProfile --region $region --query 'cluster.{Name:name,Version:version,Status:status,Health:health.issues}' --output json
kubectl version
```

Expected: `ACTIVE`, intended stage version and reachable API. Before the
control-plane stage this is the source minor; afterward it is the target. Null
cluster `Health` can mean no details were returned; retain workload/readiness
checks. The lab's kubectl 1.35.4 was supported with server 1.36 under the one-minor
client skew rule; a client change was not required solely for that pairing.

<a id="v-workers"></a>
### Worker validation

```powershell
aws eks describe-nodegroup --cluster-name $clusterName --nodegroup-name $nodeGroupName --profile $upgradeAwsProfile --region $region --query 'nodegroup.{Name:nodegroupName,Version:version,AMIRelease:releaseVersion,Status:status,Health:health.issues,Scaling:scalingConfig,Update:updateConfig}' --output json
kubectl get nodes -o wide
```

Expected: `ACTIVE`, health `[]`, intended version/release, and normal worker count
with all nodes `Ready`. Workers stay at the source after control-plane-only
updating and match the target after their stage. Normal lab count is two. Check
actual nodes as well as the node-group version.

<a id="v-addon"></a>
### Add-on validation

Set `$addonName` to each installed name from the inventory when checking all
add-ons. Check one immediately after its update, and all at closure.

```powershell
aws eks list-addons --cluster-name $clusterName --profile $upgradeAwsProfile --region $region --output table
aws eks describe-addon --cluster-name $clusterName --addon-name $addonName --profile $upgradeAwsProfile --region $region --query 'addon.{Name:addonName,Version:addonVersion,Status:status,Health:health.issues}' --output json
kubectl -n kube-system get deployments,daemonsets
```

After kube-proxy updating, also wait for its rollout:

```powershell
kubectl -n kube-system rollout status daemonset/kube-proxy --timeout=5m
```

Expected: AWS `ACTIVE`, selected package and health `[]`; the corresponding
Kubernetes workloads ready and up-to-date. For two Linux workers, kube-proxy is
2 desired, 2 updated and 2 ready. An EBS Windows DaemonSet with desired zero is
normal in this Linux lab. Inspect mapped workloads for other add-ons.

<a id="v-workloads"></a>
### Workload, ESO and storage validation

```powershell
kubectl get pods -A -o wide
kubectl -n external-secrets rollout status deployment/external-secrets --timeout=300s
kubectl -n external-secrets rollout status deployment/external-secrets-webhook --timeout=300s
kubectl -n external-secrets rollout status deployment/external-secrets-cert-controller --timeout=300s
kubectl -n wordpress get secretstore,externalsecret,pvc
kubectl -n wordpress get externalsecret wordpress-database -o 'custom-columns=NAME:.metadata.name,REFRESH_TIME:.status.refreshTime'
kubectl -n wordpress wait --for=condition=Ready secretstore/wordpress-secretsmanager --timeout=180s
kubectl -n wordpress wait --for=condition=Ready externalsecret/wordpress-database --timeout=180s
kubectl -n wordpress rollout status deployment/wordpress --timeout=600s
kubectl -n wordpress rollout status statefulset/wordpress-mariadb --timeout=600s
kubectl -n wordpress get events --sort-by=.lastTimestamp
```

Expected: running workloads ready, ESO resources `Ready`, PVCs `Bound`, no
unresolved scheduling/attachment/mount/image/authentication failures. Zero
restarts on new pods does not prove uninterrupted service; compare pod identity,
age and application observations. Correlate historical transient events with
current health and timestamps. Confirm a successful ExternalSecret refresh after
controller replacement; an old persisted `Ready` condition alone does not prove
fresh AWS synchronization. Wait for the configured refresh interval if needed.

Reconnect access in a separate terminal if needed:

```powershell
kubectl -n wordpress port-forward service/wordpress 8080:80 --address 127.0.0.1
```

Open `http://localhost:8080` and perform the [application checks](#helm-applications).
If ESO is deliberately disabled, validate the existing-secret setup instead of
waiting for absent ESO custom resources.

<a id="v-terraform"></a>
### Terraform validation

```powershell
terraform plan -detailed-exitcode
$LASTEXITCODE
```

Expected at baseline and closure: `No changes`, exit `0`. Exit `2` means changes
exist and `1` means an error. Investigate either before marking the hop complete.
This command plans; it does not apply.

<a id="backup-gate"></a>
## Backup and tested-restore gate

For valuable data, record recovery evidence before any mutation. The original
disposable lab explicitly waived database backup and write freezing; no restore
rehearsal was recorded. That historical exception is not the future default.

| Item | Required evidence | Restore validation |
| --- | --- | --- |
| Terraform/configuration | Protected state, lock file, source, values, desired manifests and image pins outside Git | Reconcile with live resources; old state alone cannot undo AWS changes |
| Database | Successful backup, source version, timestamp, matching credential/version metadata, checksum | Isolated restore with compatible clients and expected data |
| WordPress content | Matching `wp-content` archive or coordinated volume snapshot | Posts/media, login, disposable write/read |
| EBS | PV/PVC -> volume -> AZ/KMS map and completed snapshot IDs when used | New restored volumes/claims bind in the correct AZ |
| Rehearsal | Tested recovery point/procedure and measured restore time | Persistence across restored pod restart; originals intact |

Coordinate database and content recovery points. For a consistent snapshot pair,
stop writers, gracefully stop MariaDB and wait for unmount/detach. Resume writes
only after both snapshot requests succeed and enter `pending`. Require completed
snapshots and successful
isolated restoration before upgrading valuable data. A live snapshot may be
only crash-consistent; `Retain` and disk encryption are not backups. Protect
local backup files outside Git; EBS encryption does not encrypt laptop copies.

Inventory metadata without retrieving passwords:

```powershell
kubectl -n wordpress get pvc -o wide
kubectl get pv -o 'custom-columns=PV:.metadata.name,NAMESPACE:.spec.claimRef.namespace,CLAIM:.spec.claimRef.name,VOLUME:.spec.csi.volumeHandle,RECLAIM:.spec.persistentVolumeReclaimPolicy'
```

Use the actual IDs with `aws ec2 describe-volumes` to record AZ, encryption/KMS
and attachments. Follow the approved database backup procedure. MariaDB
`--single-transaction` requires transactional tables and does not protect against
concurrent DDL; include routines/events/triggers when required. Create SQL/tar
files in the Linux container and use `kubectl cp`, avoiding Windows PowerShell
5.1 redirection for those files. Relative Windows copy destinations avoid
drive-letter file-spec issues. Check native exits, matching hashes and restore
results; a nonempty dump file is insufficient.

For physical recovery, create **new** volumes from snapshots in the required AZ
and bind new PVs/claims in an isolated deployment. Keep originals intact. This
chart and ESO's namespace restriction need adaptation for an isolated restore;
changing only the namespace is insufficient. A restored MariaDB data directory
retains SQL users/passwords; initialization environment variables do not rotate
them. Validate snapshot-era credentials and KMS access.

Sources: [MariaDB dump](https://mariadb.com/docs/server/clients-and-utilities/backup-restore-and-import-clients/mariadb-dump),
[EBS snapshot preparation](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-creating-snapshot.html),
[EBS restoration](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-restoring-volume.html).

<a id="recovery"></a>
## Failure handling and recovery

Stop advancing when health or the plan is unexpected. Inspect the in-progress
AWS operation before retrying Terraform. Repair application/add-on configuration
separately when that is the cause. Kubernetes version rollback does not restore
database contents or previous workload settings. This deployment uses rendered
YAML plus kubectl, so it has no Helm release history for `helm rollback`.

| Symptom | First action |
| --- | --- |
| API timeout after ISP/VPN change | Check public egress IP against the API `/32` allowlist; review an access-only Terraform plan without an accidental version change |
| `NodeCreationFailure` / new nodes never ready | Inspect node-group health, ASG activity, AZ capacity, subnet IPs and EC2 quota |
| `PodEvictionFailure` | Inspect PDBs, unhealthy replacements, resources and volume placement; resolve the cause before considering force |
| EBS attachment/mount delays | Inspect events/VolumeAttachments and same-AZ capacity; preserve claims and avoid forced detach |
| Terraform errors while AWS is updating | Monitor the actual update, then re-plan from refreshed state |
| Application data regression | Use tested data restoration; control-plane rollback is not a data restore |

### Version rollback eligibility (reviewed 2026-10-30)

Current AWS user guides describe eligible control-plane rollback to the immediate
previous minor within seven days after an in-place upgrade. Requirements include
an eligible `ACTIVE` cluster, supported versions/features and readiness checks.
Another forward upgrade changes the boundary: after 1.34 -> 1.35 -> 1.36, the
previous minor is 1.35, not 1.34.

Before lowering the control plane, workers must be compatible with that lower
version and add-ons need their own review. Control-plane rollback preserves
current etcd/workloads/volumes; it does not rewind their contents.

Read the [current AWS rollback procedure](https://docs.aws.amazon.com/eks/latest/userguide/rollback-cluster.html)
and [managed-node rollback guidance](https://docs.aws.amazon.com/eks/latest/userguide/update-managed-node-group.html#managed-node-group-rollback)
at execution time. At this review date, the user guide described managed-node
rollback through `UpdateNodegroupVersion`, while the
[API reference](https://docs.aws.amazon.com/eks/latest/APIReference/API_UpdateNodegroupVersion.html)
still stated earlier Kubernetes/AMI versions could not be selected. Verify actual
service/Region/CLI support; do not promise arbitrary AMI downgrades or assume
reverting Terraform variables works. If managed rollback is unavailable,
separately plan replacement workers at the previous supported version while
the higher control plane still runs, then follow its supported rollback path.
Preserve required AZ, capacity, IAM and storage behavior.

After any approved emergency CLI change, reconcile Terraform pins and refreshed
state. Never restore old `terraform.tfstate` merely to attempt cloud rollback.

<a id="diagnostics"></a>
### Diagnostic commands

```powershell
kubectl -n wordpress get events --sort-by=.lastTimestamp
kubectl get volumeattachments
aws eks list-updates --name $clusterName --nodegroup-name $nodeGroupName --profile $upgradeAwsProfile --region $region --output json
```

Select the actual update ID returned, then inspect that operation:

```powershell
$updateId = 'ACTUAL_UPDATE_ID'
aws eks describe-update --name $clusterName --nodegroup-name $nodeGroupName --update-id $updateId --profile $upgradeAwsProfile --region $region --query 'update.{Status:status,Type:type,Errors:errors,Parameters:params}' --output json
```

For control-plane operations, omit `--nodegroup-name $nodeGroupName` from both AWS
commands. For an add-on, use `--addon-name $addonName` instead. Do not assume an
arbitrary first ID is the current operation. Correlate status/errors with the
stage record, then reuse the linked validation checks after resolution.
