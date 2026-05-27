#!/bin/bash
# verify-tools.sh - Verify all DevOps tools are installed correctly

set +e  # Don't exit on individual failures - we want to see all results

echo "═══════════════════════════════════════════════"
echo "  CloudVault DevOps Workstation Verification"
echo "═══════════════════════════════════════════════"

check() {
    local name=$1
    local cmd=$2
    if eval "$cmd" &>/dev/null; then
        version=$(eval "$cmd" 2>&1 | head -n1)
        printf "✅ %-15s %s\n" "$name" "$version"
    else
        printf "❌ %-15s NOT INSTALLED OR BROKEN\n" "$name"
    fi
}

echo ""
echo "--- Core Tools ---"
check "git"        "git --version"
check "curl"       "curl --version"
check "jq"         "jq --version"
check "yq"         "yq --version"
check "make"       "make --version"

echo ""
echo "--- Languages ---"
check "node"       "node --version"
check "npm"        "npm --version"
check "python3.11" "python3.11 --version"

echo ""
echo "--- Container & Orchestration ---"
check "docker"     "docker --version"
check "compose"    "docker compose version"
check "kubectl"    "kubectl version --client"
check "helm"       "helm version --short"
check "k9s"        "k9s version --short"

echo ""
echo "--- Cloud CLIs ---"
check "aws"        "aws --version"
check "azure"      "az --version"
check "eksctl"     "eksctl version"

echo ""
echo "--- IaC & Security ---"
check "terraform"  "terraform version"
check "trivy"      "trivy --version"

echo ""
echo "--- Cloud Authentication ---"
if aws sts get-caller-identity &>/dev/null; then
    account=$(aws sts get-caller-identity --query Account --output text)
    user=$(aws sts get-caller-identity --query Arn --output text)
    echo "✅ AWS authenticated: $account ($user)"
else
    echo "❌ AWS not authenticated - run 'aws configure'"
fi

if az account show &>/dev/null; then
    sub=$(az account show --query name -o tsv)
    echo "✅ Azure authenticated: $sub"
else
    echo "❌ Azure not authenticated - run 'az login'"
fi

if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "✅ GitHub SSH authenticated"
else
    echo "❌ GitHub SSH not working - check ~/.ssh/id_ed25519.pub on GitHub"
fi

echo ""
echo "═══════════════════════════════════════════════"
