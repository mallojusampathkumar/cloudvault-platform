# CloudVault Platform

A production-grade, multi-cloud microservices e-commerce platform.

## Architecture
- **Primary cloud:** AWS (EKS, RDS, ElastiCache, S3, CloudFront, Route53)
- **Secondary cloud:** Azure (AKS for DR, ACR, Key Vault, Azure Monitor)
- **CI/CD:** GitHub Actions + Jenkins + ArgoCD (GitOps) + Azure DevOps
- **IaC:** Terraform (multi-cloud modules)
- **Observability:** Prometheus + Grafana + Loki + Alertmanager
- **Security:** SonarQube, Trivy, External Secrets Operator, cert-manager

## Services
| Service | Language | Purpose |
|---------|----------|---------|
| frontend | React | User-facing UI |
| user-service | Node.js | Auth, JWT, profiles |
| product-service | Python/Flask | Catalog |
| cart-service | Node.js | Shopping cart (Redis-backed) |
| order-service | Python/FastAPI | Order lifecycle |
| payment-service | Node.js | Payment processing |
| notification-service | Python | Email/SMS via queue |

## Repository Structure
.
├── services/           # All microservice code
├── infrastructure/     # Terraform, K8s manifests, Helm charts
├── ci-cd/              # Pipeline definitions
├── monitoring/         # Observability configs
├── scripts/            # Helper scripts
├── docs/               # Architecture docs
└── runbooks/           # Incident response playbooks

## Getting Started
See `docs/SETUP.md`.
