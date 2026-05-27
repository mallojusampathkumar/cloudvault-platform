# RCA: EKS Pods Cannot Reach RDS — Security Group Mismatch

**Date:** 2026-05-27
**Component:** AWS EKS / RDS Security Groups
**Severity:** P2 (blocks all DB-dependent workloads)
**Author:** Sampath

## Summary
Pods running on EKS could not connect to RDS PostgreSQL. Connection
attempts timed out at the TCP layer.

## Symptoms
- `psql` from pod: "Operation timed out" after ~2 minutes
- Telnet to RDS port 5432 from inside pod: hangs forever
- DNS resolution worked (got correct IP)
- RDS health checks all green from AWS console

## Diagnosis Steps
1. Verified DNS resolved correctly: 10.20.12.183 ✓
2. Confirmed RDS endpoint was reachable from VPC route perspective ✓
3. Checked RDS security group inbound rules
   - Found: allows source SG sg-0115305ea625750c4 (our Terraform-created
     "cloudvault-dev-eks-nodes-sg")
4. Checked which SG was actually attached to EKS nodes
   - Found: sg-0eea9407658c694ad ("eks-cluster-sg-cloudvault-dev-eks-*")
   - This is the AWS-auto-created cluster SG, NOT our custom one
5. Root cause confirmed: SGs don't match

## Root Cause
EKS automatically creates and attaches a "cluster security group"
(named `eks-cluster-sg-<cluster-name>`) to all worker nodes on cluster
creation. To use a custom SG, you must explicitly pass it via launch
template — `aws_eks_node_group` does not accept a security group ID
directly.

Our Terraform created an `aws_security_group "eks_nodes"` and allowed
it on RDS, but never attached it to the actual nodes. The custom SG
became an orphan; the auto-created SG (which we didn't reference in
RDS rules) was what nodes actually used.

## Fix
1. Quick fix: Added inbound rule on RDS SG allowing source =
   EKS auto-created cluster SG (via `aws ec2 authorize-security-group-ingress`)
2. Permanent fix: Added a Terraform-managed rule that references
   `aws_eks_cluster.main.vpc_config[0].cluster_security_group_id` —
   this is the canonical way to get the EKS auto-created SG ID.
3. Revoked the manual rule so Terraform owns it cleanly (no drift).

## Long-Term Improvement Options
Option A: Use launch template to attach custom node SG to nodes
   (more SG control, more complexity)
Option B: Use only the EKS auto-created cluster SG and accept that
   it's our node SG (simpler, what we did)
For this project: Option B. For multi-tenant production: Option A.

## Detection
- "Connection timed out" + DNS works = security group issue 95% of the time
- AWS Reachability Analyzer (free, automated diagnosis) confirms this
- Recommendation: add automated SG-to-resource consistency check to CI

## Prevention
- Always verify SG references match actual attached SGs
- Use Terraform data sources to reference EKS-managed resources by
  computed attribute, never by hardcoded ID
- Use AWS VPC Flow Logs in staging — would have shown rejected packets

## Lessons Learned
- EKS auto-creates resources you might not realize exist
- An orphan SG (created but unattached) doesn't error — silent failure
- "Connection timed out" vs "Connection refused" — error type tells layer
- Always trace: which SG does the SOURCE actually have vs which SG does
  the DESTINATION allow — they must match
