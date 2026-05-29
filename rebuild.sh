#!/usr/bin/env bash
#
# rebuild.sh — Bring the entire CloudVault platform back from an empty AWS account.
#
# Goes: Terraform infra -> kubectl config -> CI image build -> ALB controller
#       -> base K8s (namespace, redis, nginx) -> 6 services -> ingress
#       -> ArgoCD GitOps -> monitoring.
#
# Every fix discovered during the original build is baked in, so this runs clean.
#
# USAGE:  cd ~/projects/cloudvault && bash rebuild.sh
#
# Takes ~25-30 min (EKS cluster creation alone is ~15 min). Grab a coffee.
# ----------------------------------------------------------------------------

set -euo pipefail

# ===== CONFIG (change only if your names differ) =====
AWS_ACCOUNT="806121398176"
REGION="ap-south-1"
CLUSTER="cloudvault-dev-eks"
NODEGROUP="cloudvault-dev-nodes"
ALB_ROLE="arn:aws:iam::${AWS_ACCOUNT}:role/cloudvault-dev-alb-controller-role"
NAMESPACE="cloudvault"
GRAFANA_PW="changeme-$(date +%s)"   # random-ish; change after login
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${REPO_ROOT}/infrastructure/terraform/aws/main"
K8S="${REPO_ROOT}/infrastructure/kubernetes/manifests"
HELM_CHART="${REPO_ROOT}/infrastructure/helm-charts/cloudvault-service"
HELM_VALUES="${REPO_ROOT}/infrastructure/helm-charts/values"
SERVICES="user-service product-service cart-service order-service payment-service notification-service"

say() { echo -e "\n========== $1 ==========\n"; }

# ----------------------------------------------------------------------------
say "STEP 1/9  Provision AWS infrastructure with Terraform"
cd "$TF_DIR"
terraform init -input=false
terraform apply -auto-approve
echo "Infra created."

# ----------------------------------------------------------------------------
say "STEP 2/9  Configure kubectl for the new cluster"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
echo "Waiting for nodes to be Ready..."
for i in {1..20}; do
  ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
  [ "${ready:-0}" -ge 2 ] && { echo "Nodes Ready: $ready"; break; }
  sleep 15
done
kubectl get nodes

# ----------------------------------------------------------------------------
say "STEP 3/9  Trigger CI to build + push images to ECR"
cd "$REPO_ROOT"
git commit --allow-empty -m "rebuild: trigger image build" && git push || echo "push skipped"
echo "Waiting for GitHub Actions to finish (checking every 30s, up to 6 min)..."
for i in {1..12}; do
  sleep 30
  status=$(gh run list --workflow=build-push-ecr.yml --limit 1 --json status --jq '.[0].status' 2>/dev/null || echo "unknown")
  echo "  CI status: $status ($((i*30))s)"
  [ "$status" = "completed" ] && break
done
echo "Verifying images exist in ECR..."
for svc in $SERVICES; do
  aws ecr describe-images --repository-name cloudvault/$svc --region "$REGION" \
    --image-ids imageTag=latest --query "imageDetails[0].imageSizeInBytes" --output text \
    >/dev/null 2>&1 && echo "  OK: $svc" || echo "  WARN: $svc :latest not found yet"
done

# ----------------------------------------------------------------------------
say "STEP 4/9  Install ALB controller (with explicit vpcId+region — metadata fix)"
VPC_ID=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query "cluster.resourcesVpcConfig.vpcId" --output text)
echo "VPC: $VPC_ID"
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$ALB_ROLE" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --wait --timeout 4m
kubectl get deployment -n kube-system aws-load-balancer-controller

# ----------------------------------------------------------------------------
say "STEP 5/9  Deploy base K8s resources (namespace, Redis, nginx)"
kubectl apply -f "$K8S/00-namespace.yaml"
kubectl apply -f "$K8S/10-redis.yaml"          # cart dependency (Problem 6 fix)
kubectl apply -f "$K8S/15-nginx-gateway.yaml"
kubectl rollout status deployment/redis -n "$NAMESPACE" --timeout=90s || true

# ----------------------------------------------------------------------------
say "STEP 6/9  Deploy the 6 microservices via Helm (tag: latest baked into values)"
for svc in $SERVICES; do
  echo "--- $svc ---"
  helm upgrade --install "$svc" "$HELM_CHART" \
    -f "$HELM_VALUES/$svc.yaml" \
    --namespace "$NAMESPACE" --wait --timeout 3m \
    || echo "WARN: $svc helm timed out — check 'kubectl get pods -n $NAMESPACE'"
done
kubectl get pods -n "$NAMESPACE"

# ----------------------------------------------------------------------------
say "STEP 7/9  Apply ingress (creates the public ALB)"
kubectl apply -f "$K8S/20-ingress.yaml"
echo "Waiting up to 2 min for ALB address..."
for i in {1..12}; do
  sleep 10
  ALB=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "${ALB:-}" ] && { echo "ALB: $ALB"; break; }
done
kubectl get ingress -n "$NAMESPACE"

# ----------------------------------------------------------------------------
say "STEP 8/9  Install ArgoCD + apply GitOps ApplicationSet"
kubectl create namespace argocd 2>/dev/null || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml
kubectl wait --for=condition=available --timeout=180s deployment/argocd-server -n argocd
kubectl apply -f "$REPO_ROOT/infrastructure/argocd/applications.yaml"
echo "ArgoCD apps:"
sleep 15
kubectl get applications -n argocd 2>/dev/null || echo "(apps registering...)"

# ----------------------------------------------------------------------------
say "STEP 9/9  Scale to 4 nodes + install monitoring (pod-count fix)"
aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$NODEGROUP" \
  --scaling-config minSize=2,maxSize=5,desiredSize=4 --region "$REGION"
echo "Waiting for 4 nodes..."
for i in {1..20}; do
  ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || true)
  [ "${ready:-0}" -ge 4 ] && { echo "Nodes Ready: $ready"; break; }
  sleep 15
done
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update >/dev/null
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword="$GRAFANA_PW" \
  --set prometheus.prometheusSpec.maximumStartupDurationSeconds=300 \
  --wait --timeout 6m || echo "WARN: monitoring install slow — check 'kubectl get pods -n monitoring'"

# ----------------------------------------------------------------------------
say "DONE — Platform rebuilt"
echo "Grafana admin password: $GRAFANA_PW   (change it after login)"
echo ""
echo "Get your URLs:"
echo "  Platform : kubectl get ingress -n $NAMESPACE"
echo "  ArgoCD   : kubectl patch svc argocd-server -n argocd -p '{\"spec\":{\"type\":\"LoadBalancer\"}}' && kubectl get svc argocd-server -n argocd"
echo "  Grafana  : kubectl patch svc monitoring-grafana -n monitoring -p '{\"spec\":{\"type\":\"LoadBalancer\"}}' && kubectl get svc monitoring-grafana -n monitoring"
echo ""
echo "Final pod check:"
kubectl get pods -n "$NAMESPACE"
echo ""
echo "REMEMBER: this is now costing ~ Rs 13-18/hr. Run teardown when done."
