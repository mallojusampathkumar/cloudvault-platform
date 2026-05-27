# RCA: Docker Build Failed — npm ci Lockfile Mismatch

**Date:** 2026-05-27
**Service:** user-service
**Severity:** P3 (build failure, no production impact)
**Author:** Sampath

## Summary
Docker image build failed at `RUN npm ci --only=production` step with
"package.json and package-lock.json are not in sync" error.

## Timeline
- 08:02 UTC — Local `npm start` succeeded
- 08:03 UTC — `docker build` failed at step 4/5
- 08:05 UTC — Identified lockfile mismatch
- 08:10 UTC — Fixed via exact version pinning + lockfile regeneration

## Root Cause
The package.json used semver caret (`^`) ranges. When `npm install` ran
locally, npm resolved to newer major versions than specified
(e.g., express 5.2.1 instead of 4.x). The lockfile recorded these newer
versions. `npm ci` then refused to install because lockfile contradicted
package.json declared ranges.

## Why `npm ci` (not npm install) in Docker?
- Reproducible builds — same versions every time
- Fail-fast on lockfile drift instead of silently resolving
- ~2x faster than npm install (no dependency resolution)
- Production best practice — used by every major CI/CD pipeline

## Fix
1. Removed node_modules and package-lock.json
2. Pinned exact versions in package.json (no ^ or ~)
3. Ran `npm install` to regenerate clean lockfile
4. Updated Dockerfile flag from `--only=production` (deprecated)
   to `--omit=dev`

## Prevention
- Add `.npmrc` with `save-exact=true` to force exact versions
- Add CI step: `npm ci` on every PR to catch drift early
- Document lockfile policy in CONTRIBUTING.md

## Lessons Learned
- Always commit package-lock.json (it's not optional)
- `npm install` and `npm ci` have different contracts
- Caret ranges in package.json can cause CI-only failures
