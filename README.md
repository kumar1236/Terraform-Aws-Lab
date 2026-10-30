# WordPress on EKS: local Terraform and Helm workflow

All commands below run in PowerShell from the repository root. Nothing uses
GitHub Actions. Terraform creates AWS resources; Docker builds/pushes the
WordPress image; Helm renders YAML locally; you inspect and apply it with kubectl.

## What is included

| File or directory | Purpose |
| --- | --- |
| `app/Dockerfile` | Official WordPress/PHP/Apache base pinned by digest. |
| `charts/wordpress/Chart.yaml` | Metadata for our custom local chart. |
| `charts/wordpress/values.yaml` | Image, database, disk, resource and URL settings. No passwords. |
| `charts/wordpress/values.schema.json` | Reject missing image settings and unsupported lab combinations. |
| `charts/wordpress/templates/wordpress-*.yaml` | One WordPress Deployment, ClusterIP Service and content PVC. |
| `charts/wordpress/templates/mariadb-*.yaml` | One MariaDB StatefulSet, headless Service and database PVC. |
| `charts/wordpress/templates/secretstore.yaml`, `externalsecret.yaml` | Fetch credentials from Secrets Manager through ESO. |
| `charts/wordpress/templates/storageclass.yaml` | Encrypted gp3 EBS disks using the EKS EBS CSI add-on. |
| `wordpress-secrets.tf` | Empty Secrets Manager secret, scoped ESO IAM role and EKS Pod Identity association. |
| `platform/` | ESO bootstrap namespaces, controller settings and pinned upstream chart checksum. |
| `scripts/` | Initialize passwords once and render the two manifest bundles. |

WordPress uses your ECR image. MariaDB uses the digest-pinned official
`mariadb:11.8.9` image from Docker Hub through the nodes' NAT egress.
The WordPress chart is custom and has no downloaded chart dependencies.
ESO is a separate upstream chart from https://charts.external-secrets.io,
pinned to 2.14.0 with its archive SHA256 verified.

The lab has one WordPress pod and one MariaDB pod. It does not provide
application/database high availability. WordPress uses a Recreate update
strategy because its EBS disk allows one writer. EBS disks remain in their
original AZ; the scheduler uses volume topology when restarting pods.

## 1. Create the AWS infrastructure

Requires Terraform, AWS CLI, Docker Desktop in Linux-container mode, Helm
and kubectl. Use your working AWS profile:

```powershell
$env:AWS_PROFILE = 'lab-admin'
terraform fmt -check
terraform validate
terraform plan --out=phase1.tfplan
```

Review the plan. When you are ready to create the resources, apply that plan:

```powershell
terraform apply phase1.tfplan
```

Terraform creates only the Secrets Manager secret's metadata. Password values
are initialized separately and never enter Terraform state.
Public Kubernetes API access is restricted to `49.43.227.51/32`; update
`eks.tf` and reapply if your laptop's public egress IP changes.

Connect kubectl after the cluster, nodes and managed add-ons are ready:

```powershell
$clusterName = terraform output -raw eks_cluster_name
aws eks update-kubeconfig --profile lab-admin --region ap-south-1 --name $clusterName --alias wp-lab
kubectl config current-context
kubectl get nodes
kubectl -n kube-system get pods
```

The apply identity initially has cluster administrator access. Check the context
before running the deployment commands.

## 2. Initialize database passwords once

```powershell
$secretName = terraform output -raw wordpress_database_secret_name
.\scripts\Initialize-WordPressSecret.ps1 -SecretId $secretName
```

The initializer generates separate random root/application passwords, uses a
temporary file restricted to your Windows user, uploads them with `lab-admin`,
and deletes that file. It refuses to overwrite any existing secret version.
It does not print passwords. JSON properties are `root-password` and
`wordpress-password`.

The default chart points to `wp-lab/wordpress/database`. If you change
Terraform's `project`, set `externalSecrets.secretName` to the resulting name
in an optional `charts/wordpress/values.local.yaml` file (ignored by Git).

## 3. Build and upload the WordPress image from your laptop

```powershell
$ecrRepository = terraform output -raw ecr_repository_url
$ecrRegistry = ($ecrRepository -split '/')[0]
$imageTag = 'lab-' + (Get-Date -Format 'yyyyMMdd-HHmmss')

docker build --platform linux/amd64 -t "${ecrRepository}:$imageTag" .\app
```

After the build succeeds, authenticate and push:

```powershell
.\scripts\Connect-Ecr.ps1 -Registry $ecrRegistry

docker push "${ecrRepository}:$imageTag"
```

Check each command succeeds before continuing. ECR tags are immutable; keep the
same tag for this deployment and use a new unique tag for a changed build.
The worker IAM role pulls the image. WordPress itself receives no AWS keys.

The script downloads AWS's ECR credential helper 0.12.0 into the ignored
local cache and verifies its pinned SHA256. It checks registry authentication
and configures only this registry in your Docker config; other Docker login
settings are preserved. It selects `lab-admin` and disables the helper's token
file cache for the current terminal. No manual `docker login` is required.

The wrapper explicitly prevents a UTF-8 BOM on the registry input, including Windows PowerShell 5.1 with console code page 65001.

Rerun `Connect-Ecr.ps1` in each new PowerShell window before pushing or pulling
from ECR; it puts the cached helper on that terminal's PATH and selects the AWS
profile. Windows PowerShell password pipes can change encoding, and Windows
Credential Manager limits individual credential blobs to 2,560 bytes. ECR
passwords can exceed that limit. The ECR helper avoids both issues without
writing password files or putting passwords in command arguments.

## 4. Render locally

```powershell
.\scripts\Render-ExternalSecrets.ps1
.\scripts\Render-WordPress.ps1 -ImageRepository $ecrRepository -ImageTag $imageTag
```

If you created local overrides, append
`-ValuesFile .\charts\wordpress\values.local.yaml` to the WordPress command.
The renderer runs strict lint with the same values and Kubernetes 1.36
capabilities, then writes UTF-8 YAML. It requires your ECR repository and tag;
it does not invent an account ID or depend on Terraform state.

Inspect `rendered/external-secrets.yaml` and `rendered/wordpress.yaml`.
These contain secret references, not password values. The downloaded chart
cache and rendered directory are ignored by Git.

The equivalent core Helm commands are:

```powershell
helm lint .\charts\wordpress --strict --namespace wordpress --kube-version 1.36.0 --set-string "image.repository=$ecrRepository" --set-string "image.tag=$imageTag"

helm template wordpress .\charts\wordpress --namespace wordpress --kube-version 1.36.0 --set-string "image.repository=$ecrRepository" --set-string "image.tag=$imageTag"
```

The second command prints YAML; the script saves it without Windows PowerShell's
legacy redirection encoding. Rendering does not contact EKS or validate against
the running API server. It does not create a Helm release or Helm rollback
history, and plain kubectl apply does not prune objects removed from templates.

## 5. Install ESO before the application custom resources

Run these only against the intended cluster:

```powershell
kubectl apply --server-side -f .\platform\namespaces.yaml
kubectl apply --server-side -f .\rendered\external-secrets.yaml

kubectl wait --for=condition=Established --timeout=180s crd/secretstores.external-secrets.io crd/externalsecrets.external-secrets.io

kubectl -n external-secrets rollout status deployment/external-secrets --timeout=300s
kubectl -n external-secrets rollout status deployment/external-secrets-webhook --timeout=300s
kubectl -n external-secrets rollout status deployment/external-secrets-cert-controller --timeout=300s
```

Large ESO CRDs require server-side apply. Do not add `--force-conflicts`
automatically; review ownership conflicts if any occur.

The ESO controller service account is `external-secrets` in namespace
`external-secrets`, matching Terraform's Pod Identity association. Its role
can read only the one database secret. The controller watches the `wordpress`
namespace; the SecretStore intentionally has no static AWS credentials or
serviceAccountRef. Keep these namespace/service-account names aligned when
customizing the setup.

ESO remains pinned to chart 2.14.0. The Kubernetes version used for rendering
does not establish runtime compatibility or upstream test coverage. Review the
upstream support matrix for the pinned release and verify the controller
rollouts plus SecretStore/ExternalSecret readiness on the upgraded cluster.
See https://external-secrets.io/latest/introduction/stability-support/.

## 6. Check against EKS, then apply the application

With ESO CRDs/controllers ready:

```powershell
kubectl apply --dry-run=server -f .\rendered\wordpress.yaml
kubectl apply -f .\rendered\wordpress.yaml

kubectl -n wordpress wait --for=condition=Ready secretstore/wordpress-secretsmanager --timeout=180s
kubectl -n wordpress wait --for=condition=Ready externalsecret/wordpress-database --timeout=180s
kubectl -n wordpress rollout status statefulset/wordpress-mariadb --timeout=600s
kubectl -n wordpress rollout status deployment/wordpress --timeout=600s
kubectl -n wordpress get pods,svc,pvc
```

The PVCs use WaitForFirstConsumer, so binding waits until pods are scheduled.
Do not wait for PVC binding before applying the workloads. If resources fail
to become ready, inspect `kubectl -n wordpress get events --sort-by=.lastTimestamp`
and `kubectl -n wordpress describe pod <pod-name>`.

## 7. Access WordPress

```powershell
kubectl -n wordpress port-forward service/wordpress 8080:80 --address 127.0.0.1
```

Keep that terminal open and visit http://localhost:8080. Complete the WordPress
setup wizard to choose your site administrator credentials; these are separate
from the database passwords. No ALB, Ingress or public application port is
created. Your public IP is used only for the EKS API allowlist.

## EKS upgrades

Use the [reusable EKS upgrade process](docs/eks-upgrade-process.md) for future
minor-version upgrades. It defines shared procedures and validation commands
once, covering readiness, staged Terraform plans, workers, add-ons, application
checks, and recovery considerations.

The [completed 1.34 -> 1.35 -> 1.36 lab record](docs/eks-upgrade-record.md)
links each historical stage to those procedures and includes a future-record
template.

## Updates and data

- For a new image, build/push with a new tag, rerun the renderer using that tag,
inspect the diff, and apply the new YAML. Expect a brief WordPress interruption.
- WordPress uploads/themes/plugins live on its `wp-content` PVC. Core files come
from the container image; core auto-updates are disabled for image-based updates.
Persisted plugin/theme directories take precedence over copies in a new image.
- MariaDB stores data on its own PVC. Database name, user and password environment
variables initialize an empty disk only. Updating Secrets Manager/ESO does not
rotate existing SQL users or refresh running pods' environment variables.
Perform coordinated SQL password rotation and workload restarts separately;
never rerun initialization to reset a running database.
- PVCs are not backups. The StorageClass uses Retain; retained EBS volumes continue
to cost money until explicitly removed. StatefulSet scaling/deletion retains its
PVC. Deleting the namespace deletes its PVC objects; retain policy preserves
underlying volumes but recovery requires deliberate PV/PVC work.

## Alternative: use an existing Kubernetes Secret

Skip step 2 (Secrets Manager initialization) and step 5 (ESO installation).
Ensure the namespace exists before provisioning the existing Secret:

```powershell
kubectl create namespace wordpress --dry-run=client -o yaml | kubectl apply -f -
```

The existing Secret must be in `wordpress` and contain `root-password` and
`wordpress-password`. Provision its values through your chosen secret-management
process; do not put passwords in command history or chart values.

Create `charts/wordpress/values.local.yaml` with metadata only:

```yaml
externalSecrets:
  enabled: false
secrets:
  existingSecret: already-present-db
```

Render only the WordPress bundle with `-ValuesFile` pointing to that file.
Then follow step 6, skipping both the SecretStore and ExternalSecret waits;
keep the database and WordPress rollout checks. This mode renders neither ESO
custom resource and requires no ESO controller.

## Validation scope

Local Helm lint/render checks target Kubernetes 1.36 capabilities. They do not
validate against the live API server or prove AWS permissions, image pulls, EBS
provisioning, database initialization, or application behavior on the upgraded
cluster. Use the server-side dry-run and readiness checks above to validate
against EKS. No infrastructure apply, image upload, password initialization or
Kubernetes deployment is performed by creating these files.
