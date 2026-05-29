# CloudVault — Complete Project Documentation & Learning Guide

> A multi-cloud, production-grade e-commerce microservices platform built to demonstrate end-to-end Cloud and DevOps engineering: infrastructure-as-code, containers, Kubernetes, CI/CD, GitOps, and observability — all working together on AWS.

This document explains **what was built, why each piece exists, and every problem that came up and how it was solved** — in plain language. For the actual commands and configuration files, see the separate *CloudVault Code Reference*.

---

## 1. What CloudVault Is (The One-Paragraph Version)

CloudVault is an online-store backend split into **six independent services** — users, products, cart, orders, payments, and notifications. Instead of one big application, each piece runs on its own, can be updated on its own, and scales on its own. These services run inside a **Kubernetes cluster on AWS**, are built and shipped automatically when code changes, are kept in sync with Git by a GitOps tool, and are watched live by a monitoring stack. In short: it is a small but complete picture of how modern companies actually run software in production.

The point of the project was never the online store itself. The point was to **touch every layer a Cloud/DevOps engineer is responsible for**, hit the real problems those layers throw at you, and solve them. That is what makes it a credible representation of hands-on experience.

---

## 2. How This Maps to a Career Story

The work naturally splits into two professional identities, which is exactly how it should be presented:

| Role | What it covers in this project |
|------|-------------------------------|
| **Cloud / Infrastructure Engineer** | Designing and provisioning the AWS foundation with Terraform — networking (VPC, subnets), the Kubernetes cluster (EKS), databases, IAM roles, load balancers. The "build the ground everything stands on" role. |
| **DevOps Engineer** | Everything that moves code and keeps it running — CI/CD pipelines, containers, Kubernetes deployments, GitOps with ArgoCD, monitoring with Prometheus/Grafana, and incident handling. The "ship it and keep it healthy" role. |

A single project covering both is stronger than two thin ones, because it shows you understand how the layers connect — which is the thing experienced engineers actually have that juniors don't.

---

## 3. The Full Stack — What Each Layer Is and Why It Exists

Think of it as a stack, bottom to top. Each layer has one job.

**Layer 1 — Terraform (the foundation).**
*Purpose: define all cloud infrastructure as code so it is reproducible.* Instead of clicking around the AWS console, every resource — the network, the cluster, the database, the security rules — is written in files. Run one command and 54 resources appear, configured identically every time. This is "Infrastructure as Code." Its real value showed up later: when the cluster needed rebuilding, it was one command, not a day of manual clicking.

**Layer 2 — AWS networking (VPC, subnets, security groups).**
*Purpose: a private, secure network for everything to live in.* The VPC is your own isolated section of AWS. Subnets divide it (public-facing vs private). Security groups are firewalls deciding what can talk to what. Nothing runs "on the open internet" by accident — traffic flows only where you allow it.

**Layer 3 — EKS (the Kubernetes cluster).**
*Purpose: run and manage containers across multiple machines.* EKS is AWS's managed Kubernetes. It is the "operating system for your containers" — it decides which machine each service runs on, restarts anything that crashes, runs multiple copies for reliability, and replaces failed machines. The cluster ran on worker nodes (the actual virtual machines), starting at 2 and later scaled to 4.

**Layer 4 — Container images in ECR.**
*Purpose: store the packaged services so the cluster can pull them.* Each service is packaged into a container image (its code + everything it needs to run). ECR is AWS's private registry where those images live. Kubernetes pulls images from here to run them.

**Layer 5 — The six microservices + Redis + NGINX gateway.**
*Purpose: the actual application.* Six API services, each running two copies for reliability. Redis is a fast in-memory store the cart uses. The NGINX gateway sits in front and routes internal traffic.

**Layer 6 — ALB Ingress (the public front door).**
*Purpose: let the outside world reach the services safely.* The Application Load Balancer is the single public entry point. A request from the internet hits the ALB, which forwards it to the right service inside the cluster. Without this, the platform would run but be unreachable.

**Layer 7 — GitHub Actions (CI/CD).**
*Purpose: automatically build and ship code.* When you push code to GitHub, this automatically builds fresh container images and pushes them to ECR. No manual building. This is the "CI" (Continuous Integration) half.

**Layer 8 — ArgoCD (GitOps / Continuous Deployment).**
*Purpose: make the cluster always match what's in Git.* ArgoCD watches your Git repository and continuously ensures the running cluster matches what the repo says it should be. Change a file in Git, and ArgoCD applies it. If someone changes the cluster by hand, ArgoCD notices the drift. **Git becomes the single source of truth** — this is the core idea of GitOps, and it is what senior environments run on.

**Layer 9 — Prometheus + Grafana (observability).**
*Purpose: see what's happening, live.* Prometheus collects metrics (CPU, memory, request counts) from everything. Grafana turns those into dashboards you can look at. This is how you know the platform is healthy — and how you catch problems before users do.

---

## 4. The Journey, Phase by Phase

### Phase 1 — Build and test locally
The six services were written and packaged into container images. **Multi-stage Docker builds** were used to shrink images dramatically (roughly 500MB down to 150MB) — smaller images pull faster and are more secure. Everything was tested together on the local machine using **docker-compose** before any cloud was touched.

*Why this order:* you never debug code for the first time in the cloud. You prove it works locally — fast, free, simple — then move it up.

### Phase 2 — Lay the cloud foundation with Terraform
The entire AWS environment was defined in code: the network, the EKS cluster, the database, IAM roles, security groups. One `terraform apply` created it all (54 resources). This is the Cloud/Infrastructure Engineer half of the work.

### Phase 3 — Get the cluster running and reachable
The container images were built by GitHub Actions and pushed to ECR. The services were deployed onto the EKS cluster. The ALB ingress controller was installed to create the public front door. This phase is where most of the hard problems appeared (see Section 5) — installing the load balancer controller and getting images to deploy cleanly is genuinely the trickiest part of EKS work.

### Phase 4 — Add GitOps with ArgoCD
ArgoCD was installed and pointed at the Git repository. From this point, the cluster's desired state lives in Git, and ArgoCD keeps reality matched to it. A push to GitHub now flows all the way to running pods automatically.

### Phase 5 — Add monitoring
The full Prometheus + Grafana stack was installed, giving live dashboards of cluster and service health. This completes the picture — you can now not just run the platform but *observe* it.

**End state:** every layer live and connected. Public APIs returning healthy responses, a GitOps dashboard showing all services in sync, and live metrics dashboards. The complete DevOps lifecycle, working.

---

## 5. Problems Faced and How They Were Resolved

This is the most important section. **The bugs are the experience.** Anyone can follow a tutorial; being able to diagnose and fix these is what separates real engineers. Each one below is a story worth being able to tell.

**Problem 1 — The load balancer controller kept crashing (metadata timeout).**
The AWS Load Balancer Controller tries to auto-discover which network and region it's in by asking the machine's internal metadata service. On this setup, that request kept timing out, so the controller crash-looped.
*Fix:* stop making it guess. The network ID and region were passed to it explicitly during install, so it never needed to ask the metadata service. *Lesson: when automatic discovery is flaky, hardcoding known values is more reliable than runtime discovery.*

**Problem 2 — The controller started but got "permission denied" (403) from AWS.**
Once running, the controller couldn't actually create the load balancer — AWS rejected it. The cause was a version mismatch: the permissions policy that was downloaded was for an older controller version and was missing a handful of newer permissions the installed version needed.
*Fix:* the missing permissions were added to the controller's IAM role, and it was restarted to pick them up. *Lesson: always match the permissions policy version to the exact version of the tool you're installing.*

**Problem 3 — Helm commands timing out and locking up on a fresh cluster.**
Right after the cluster was rebuilt, deployment commands kept failing with "context deadline exceeded" and "another operation in progress." A brand-new cluster's control plane is briefly overloaded, so commands time out and leave locks behind that block the next command.
*Fix:* give the cluster a few minutes to stabilize, release the stuck locks, and use lighter deployment commands that don't wait and time out. *Lesson: fresh clusters need a moment to settle; don't hammer them.*

**Problem 4 — Services stuck on "ImagePullBackOff" (wrong image tags).**
Three services wouldn't start because Kubernetes couldn't find the right image to pull. Investigation revealed something subtle: the images in the registry had no usable version tag, and an attempt to fix the tags accidentally grabbed the wrong artifact — a tiny "attestation" file (about 12KB) instead of the real 49MB application image. The giveaway was the size: a real service image is megabytes, not kilobytes.
*Fix:* the deployments were pointed at the `latest` tag, which correctly referenced the real, full-size image that was already proven to work. *Lesson: image size is a fast sanity check — if it's far too small, you're pointing at the wrong thing.*

**Problem 5 — One service had no deployment at all.**
The order service simply wasn't there. An earlier deployment had failed midway and left things in a half-finished state, so the deployment was never created.
*Fix:* the stuck state was cleared and the service was deployed fresh. *Lesson: failed deployments can leave gaps, not just errors — always verify what actually exists afterward.*

**Problem 6 — The cart service crash-looped looking for "redis".**
The cart kept crashing with "host not found: redis." The cart was written expecting a Redis database at the address `redis`, but no Redis existed anywhere in the cluster.
*Fix:* a small Redis instance was deployed inside the cluster, named exactly `redis` so the cart's existing configuration found it with no code change. *Lesson: a service is only as healthy as its dependencies — a perfectly good service will crash if what it depends on is missing.*

**Problem 7 — The platform was unreachable from the browser (but actually fine).**
After everything was deployed, requests from the local machine returned nothing (code 000). But checking the load balancer showed it was active and its targets were healthy. The real cause was **DNS propagation delay** — the load balancer's web address was brand new and the local machine's DNS hadn't learned it yet.
*Fix:* resolving the address through a public DNS server and hitting it directly returned a healthy 200, proving the platform worked. It was a local caching delay, not a platform fault. *Lesson: when everything internal looks healthy but you can't reach it, suspect DNS before assuming the system is broken. "It works, your laptop just doesn't know the address yet" is a real and common situation.*

**Problem 8 — After a rebuild, the load balancer controller and ingress were gone.**
Rebuilding the cluster wiped these out, so no public front door existed.
*Fix:* the controller was reinstalled (with the explicit network/region settings from Problem 1) and the ingress was reapplied, bringing the public address back. *Lesson: know which things live in the cluster vs in your infrastructure code — cluster rebuilds wipe the former.*

**Problem 9 — ArgoCD couldn't read the Git repository ("authentication required").**
ArgoCD failed to sync because it couldn't clone the repo — the repo was private.
*Fix:* the repository was first scanned for any accidentally-committed secrets (it was clean — the only "password" hits were harmless local-dev values and normal code), then made public so ArgoCD could read it. *Lesson: before making any repo public, always scan its history for leaked credentials — exposed AWS keys get abused within minutes.*

**Problem 10 — ArgoCD synced but pods then failed to pull images.**
Once ArgoCD took over, it deployed what Git declared — but Git declared image version `0.1.0`, which had never actually been built and pushed. The new pods couldn't find it. Importantly, **the old pods kept running the whole time** — Kubernetes refuses to kill working pods until the replacements are healthy. That safety behavior meant zero downtime even during the failure.
*Fix:* the configuration files were updated to the `latest` tag that genuinely exists, committed to Git, and ArgoCD reconciled cleanly. *Lesson: GitOps deploys exactly what Git says — so Git must declare something real. Also: rolling updates protect you; a bad deploy doesn't take the old version down.*

**Problem 11 — Monitoring pods stuck "Pending" — but not for the reason it looked like.**
The Prometheus stack wouldn't schedule. The obvious guess is "not enough CPU/memory," but the nodes were only 17-37% used. The real cause was a **pod-count limit**: the chosen machine type caps how many pods it can host (based on its networking capacity, not its CPU/RAM), and both nodes were full at that cap.
*Fix:* the cluster was scaled from 2 nodes to 4, adding pod capacity. A nice detail: the Terraform was already written to allow manual scaling without conflict, so this didn't break the infrastructure-as-code. *Lesson: "Pending" doesn't always mean low resources — on Kubernetes, the number of pods a node can run is also capped, independently of CPU and memory.*

---

## 6. Concepts That Tripped You Up — Now Made Clear

These are the exact things you asked about during the build. Understanding these closes the real gaps.

**docker-compose vs Kubernetes — where did things actually run?**
You used docker-compose **only on your local machine**, early on, to build and test the services together before touching the cloud. On AWS, docker-compose was **not** used — Kubernetes (EKS) ran everything instead. The *same container images* run in both; what changes is the **orchestrator**. Compose is for one machine, development, quick testing. Kubernetes is for many machines, production — it adds self-healing, scaling, rolling updates, and load balancing. You don't "convert" compose into Kubernetes; you write Kubernetes instructions that point at the same images. **One sentence for interviews:** *"docker-compose for the local inner loop, Kubernetes for production orchestration — same images, different orchestrator."*

**Where is the frontend / client UI?**
There isn't one, and that's fine. CloudVault is a **backend platform** — six APIs that return data (JSON), not web pages. It's like a fully working restaurant kitchen with no dining room. For Cloud/DevOps roles, the backend *is* the story; nobody hiring for those roles needs a pretty UI. A real product would add a separate frontend app that *calls* these APIs, but that's a different (frontend) skill set and isn't what this project is demonstrating.

**How do you access the platform on the web?**
Through the public address that the load balancer (ALB) provides. Each public-facing piece — the platform APIs, the ArgoCD dashboard, the Grafana dashboard — got its own public web address. You open that address in a browser. The one catch you hit: a brand-new address takes a few minutes for your local machine's DNS to learn, which is why it briefly seemed unreachable even though it was working.

**Why did the same URL fail and then work?**
DNS propagation. The address existed and the platform was healthy, but your laptop's DNS cache hadn't caught up. Once it did (or once you resolved it through a public DNS server), it worked. This is normal and not a bug.

**Why `latest` for image tags — and why it's not ideal long-term.**
Pointing at `latest` was the fast way to get unblocked, because it reliably referenced the real, working image. But in proper production GitOps you'd pin an **immutable, specific version tag** (like a commit ID) so you always know exactly which version is running and can roll back precisely. *Worth saying in an interview:* *"I used `latest` to stabilize quickly, but production GitOps should pin immutable version tags for traceability and clean rollbacks."* Saying that shows you know the difference between "make it work now" and "do it right."

---

## 7. How to Talk About This (Turning the Build Into a Narrative)

When describing this work, lead with **what you built and the problems you solved**, not buzzwords. The bugs in Section 5 are your strongest material — they prove you've done the real thing, because these are the exact issues that come up in actual jobs.

A strong way to frame the whole project in a few sentences:

> *"I built and operated a production-style microservices platform on AWS EKS — six containerized services, fronted by an application load balancer, provisioned entirely with Terraform as infrastructure-as-code. I set up the full delivery pipeline: GitHub Actions builds and pushes images to ECR, and ArgoCD handles GitOps deployment so the cluster always matches Git. I added Prometheus and Grafana for observability. Along the way I debugged real production issues — load balancer controller crashes from metadata timeouts, IAM permission mismatches, image-pull failures, a missing cache dependency, DNS propagation, and node pod-count limits — and resolved each methodically."*

That paragraph is honest, specific, and covers both the Cloud Engineer and DevOps Engineer scope.

When asked about a specific hard problem, pick one from Section 5 and tell it as: **what broke → how you diagnosed it → what the root cause was → how you fixed it → what you learned.** That structure is what interviewers are listening for.

---

## 8. The Tools, In One Line Each (Quick Glossary)

- **Terraform** — write your cloud infrastructure as code; create or destroy it all with one command.
- **AWS VPC / subnets / security groups** — your private, firewalled network on AWS.
- **EKS (Kubernetes)** — runs your containers across machines; self-heals, scales, load-balances.
- **Container image** — your service packaged with everything it needs to run.
- **ECR** — AWS's private storage for your container images.
- **docker-compose** — runs containers together on one machine, for local development.
- **NGINX gateway** — routes traffic between services inside the cluster.
- **ALB / Ingress** — the public web address and front door into the cluster.
- **GitHub Actions** — automatically builds and ships your code when you push (CI).
- **ArgoCD** — keeps the cluster matching Git automatically (GitOps / CD).
- **Redis** — a fast in-memory data store; here, the cart's backing store.
- **Prometheus** — collects live metrics from everything.
- **Grafana** — turns those metrics into dashboards you can watch.

---

## 9. Where to Find the Code

This document deliberately contains **no commands or configuration** — it's the "understand it and explain it" reference. For the actual implementation — Terraform files, Kubernetes manifests, Helm values, the CI/CD pipeline definition, and the exact commands used — see the separate **CloudVault Code Reference** document.

---

*Built across the full Cloud + DevOps lifecycle: infrastructure-as-code → containers → Kubernetes → CI/CD → GitOps → observability. Every layer live, every layer connected, every problem along the way diagnosed and resolved.*
