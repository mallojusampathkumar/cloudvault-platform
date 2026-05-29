# CloudVault — Code Reference

> Companion to *CloudVault-Documentation.md*. That document explains the **what and why** in plain language. This one holds the **how** — the commands, the file layout, and the exact rebuild sequence. Read the other doc first to understand the concepts; use this one when you're at the keyboard.

---

## 0. Set These Once

Before running anything, know these values (find your account ID with `aws sts get-caller-identity --query Account --output text`):

| Variable | Value |
|----------|-------|
| AWS account ID | `806121398176` |
| Region | `ap-south-1` (Mumbai) |
| Cluster name | `cloudvault-dev-eks` |
| Node group | `cloudvault-dev-nodes` |
| ECR registry | `806121398176.dkr.ecr.ap-south-1.amazonaws.com` |
| State bucket (S3) | `cloudvault-tfstate-addf753d` |
| State lock table | `cloudvault-tflock` |
| ALB controller IAM role | `cloudvault-dev-alb-controller-role` |
| GitHub repo | `github.com/mallojusampathkumar/cloudvault-platform` |

---

## 1. Repository Layout

```
cloudvault/
├── .github/workflows/
│   └── build-push-ecr.yml        CI: build images, push to ECR
├── services/                     6 microservices (Node.js + Dockerfile each)
│   ├── user-service/
│   ├── product-service/
│   ├── cart-service/
│   ├── order-service/
│   ├── payment-service/
│   └── notification-service/
├── docker-compose.yml            Local-only: run all services together to test
└── infrastructure/
    ├── terraform/aws/main/       The cloud foundation (see Section 2)
    ├── kubernetes/manifests/     Raw K8s YAML (namespace, redis, nginx, ingress)
    ├── helm-charts/
    │   ├── cloudvault-service/   One reusable chart for all services
    │   └── values/               Per-service config (user-service.yaml, etc.)
    └── argocd/
        └── applications.yaml     ArgoCD ApplicationSet (GitOps definition)
```

---

## 2. Terraform Files and What Each Provisions

All under `infrastructure/terraform/aws/main/`:

| File | What it creates |
|------|-----------------|
| `backend.tf` | Tells Terraform to store state in the S3 bucket + DynamoDB lock |
| `providers.tf` | AWS provider config |
| `variables.tf` | Inputs: node sizes, region, names |
| `vpc.tf` | The private network |
| `security.tf` | Security groups (firewalls) |
| `eks.tf` | The Kubernetes cluster + worker node group |
| `ecr.tf` | The 6 container image repositories |
| `rds.tf` | PostgreSQL database |
| `secrets.tf` | Auto-generated DB password |
| `iam.tf` | IAM roles (cluster, nodes, OIDC for GitHub) |
| `alb-controller.tf` | IAM role for the load balancer controller |
| `alb-extra-permissions.tf` | The extra ELB permissions (the fix from Problem 2) |
| `outputs.tf` | Prints cluster endpoint, etc. after apply |

**Key behavior:** `eks.tf` has `ignore_changes = [scaling_config[0].desired_size]` on the node group. This is why manually scaling 2→4 nodes did **not** conflict with Terraform — it deliberately lets you scale without `terraform apply` reverting it.

---

## 3. The Rebuild Sequence (Manual Walkthrough)

This is what `rebuild.sh` automates. Understanding the order matters — each step depends on the one before.

**Step 1 — Provision infrastructure.**
```
cd infrastructure/terraform/aws/main
terraform init       # connects to the S3 state backend
terraform apply -auto-approve   # creates all 54 resources (~15-20 min, EKS is slow)
```

**Step 2 — Point kubectl at the new cluster.**
```
aws eks update-kubeconfig --name cloudvault-dev-eks --region ap-south-1
kubectl get nodes    # confirm nodes are Ready
```

**Step 3 — Build + push images (CI does this, or trigger it).**
```
git commit --allow-empty -m "trigger build" && git push
# GitHub Actions builds all 6 images and pushes to ECR
# Verify: aws ecr describe-images --repository-name cloudvault/user-service --region ap-south-1
```

**Step 4 — Install the ALB controller (with the metadata fix).**
The critical flags are `region` and `vpcId` passed explicitly — this avoids the metadata-timeout crash (Problem 1). Get the VPC ID first:
```
VPC_ID=$(aws eks describe-cluster --name cloudvault-dev-eks --region ap-south-1 \
  --query "cluster.resourcesVpcConfig.vpcId" --output text)
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=cloudvault-dev-eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::806121398176:role/cloudvault-dev-alb-controller-role" \
  --set region=ap-south-1 \
  --set vpcId=$VPC_ID \
  --wait --timeout 3m
```

**Step 5 — Deploy base K8s resources (namespace, Redis, nginx).**
```
kubectl apply -f infrastructure/kubernetes/manifests/00-namespace.yaml
kubectl apply -f infrastructure/kubernetes/manifests/10-redis.yaml   # cart's dependency (Problem 6 fix)
kubectl apply -f infrastructure/kubernetes/manifests/15-nginx-gateway.yaml
```

**Step 6 — Deploy the 6 services via Helm.**
Each uses the shared chart + its own values file (all now correctly set to `tag: "latest"` — Problem 10 fix).
```
for svc in user-service product-service cart-service order-service payment-service notification-service; do
  helm upgrade --install $svc infrastructure/helm-charts/cloudvault-service \
    -f infrastructure/helm-charts/values/$svc.yaml \
    --namespace cloudvault --wait --timeout 3m
done
```

**Step 7 — Apply the ingress (creates the public ALB).**
```
kubectl apply -f infrastructure/kubernetes/manifests/20-ingress.yaml
# Wait ~2 min, then: kubectl get ingress -n cloudvault  → shows the public address
```

**Step 8 — Install ArgoCD + apply the GitOps definition.**
```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml
kubectl wait --for=condition=available --timeout=180s deployment/argocd-server -n argocd
kubectl apply -f infrastructure/argocd/applications.yaml   # the ApplicationSet → 6 apps
```

**Step 9 — Install monitoring (needs 4 nodes — Problem 11).**
Scale to 4 nodes first so the monitoring pods fit (pod-count limit, not CPU):
```
aws eks update-nodegroup-config --cluster-name cloudvault-dev-eks \
  --nodegroup-name cloudvault-dev-nodes \
  --scaling-config minSize=2,maxSize=5,desiredSize=4 --region ap-south-1
# wait for 4 nodes Ready, then:
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=CHANGE_ME --wait --timeout 5m
```

**Step 10 — Get your access URLs.**
```
kubectl get ingress -n cloudvault     # platform APIs
kubectl get svc argocd-server -n argocd       # (patch to LoadBalancer for UI)
kubectl get svc monitoring-grafana -n monitoring   # (patch to LoadBalancer for UI)
```

---

## 4. The Teardown Sequence (Back to Zero Cost)

Order matters — delete K8s load balancers **first**, or they orphan ALBs that keep billing.

```
# 1. Delete LoadBalancer services + ingress (frees ALBs)
kubectl delete svc argocd-server -n argocd
kubectl delete svc monitoring-grafana -n monitoring
kubectl delete ingress --all -n cloudvault
# 2. Uninstall ALB controller
helm uninstall aws-load-balancer-controller -n kube-system
# 3. Wait 60s for AWS to remove the load balancers
# 4. Destroy all infra
cd infrastructure/terraform/aws/main && terraform destroy -auto-approve
```

**Verify zero:** these should all return empty —
```
aws eks list-clusters --region ap-south-1
aws ec2 describe-instances --region ap-south-1 --filters "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId"
aws elbv2 describe-load-balancers --region ap-south-1 --query "LoadBalancers[*].LoadBalancerName"
```

**Keep:** the S3 state bucket and DynamoDB lock table. They cost effectively nothing and are needed to rebuild.

---

## 5. Known Fixes Baked In (So Rebuild Is Clean)

These were the live problems; here's where each fix now lives permanently:

| Original problem | Permanent fix location |
|-----------------|------------------------|
| ALB controller metadata crash | `region` + `vpcId` flags in Step 4 |
| ALB controller 403 permissions | `alb-extra-permissions.tf` |
| Redis missing (cart crash) | `kubernetes/manifests/10-redis.yaml` (in Git) |
| Image tag `0.1.0` didn't exist | all `helm-charts/values/*.yaml` set to `tag: "latest"` |
| Monitoring pods Pending | scale to 4 nodes before installing (Step 9) |
| ArgoCD couldn't clone | repo is public |
| ArgoCD config lost | `argocd/applications.yaml` (in Git) |

---

## 6. The CI/CD Workflow — One Known Improvement

`.github/workflows/build-push-ecr.yml` currently tags images with the **full** Git commit SHA, while the deployment expects a **short** SHA. Today this was worked around by using `:latest`. The proper fix (do it in a calm session): add a step that computes the short SHA and use that in the image tags, so every build is traceable to a specific commit and rollbacks are precise. Until then, `:latest` works but doesn't tell you *which* version is running — fine for a demo, not ideal for real production.

---

*Use this alongside the learning doc. The learning doc tells the story; this tells the keys.*
