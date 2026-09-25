# CI/CD — GitHub Actions deploy pipeline

## Branches

| Branch | Deploys to | Trigger |
|---|---|---|
| `main` | `condor-qas` (sandbox) | automatic, on every push/merge |
| `production` | `mi-org` (production) | automatic, on every push — but `production` is a protected branch: it can only be updated via a merged PR from `main`, and the deploy job itself requires manual approval via the `production` GitHub Environment |

To promote a change to production: open a PR from `main` → `production` and merge it. That merge is the explicit go-ahead — nothing deploys to `mi-org` without it, and the job then still waits for your approval in the Environment before it runs.

## Auth

Each org authenticates via OAuth 2.0 JWT Bearer Flow, using a dedicated Connected App (`GitHub Actions Deploy`) separate from MGAgencia's own integration Connected App — different credential, different blast radius, so a compromised CI secret can't be used to call the Lead API and a compromised integration credential can't deploy metadata.

Secrets live in the GitHub repo (Settings → Secrets and variables → Actions), never in the repo itself:

| Secret | Org | Value |
|---|---|---|
| `SF_CONSUMER_KEY_QAS` | condor-qas | Consumer Key of `GitHub Actions Deploy` in condor-qas |
| `SF_JWT_KEY_QAS` | condor-qas | Private key (PEM) matching the cert uploaded to that Connected App |
| `SF_USERNAME_QAS` | condor-qas | `adminsalesforce@condor.com.py.qas` |
| `SF_INSTANCE_URL_QAS` | condor-qas | `https://condorsaci--qas.sandbox.my.salesforce.com` |
| `SF_CONSUMER_KEY_PROD` | mi-org | Consumer Key of `GitHub Actions Deploy` in mi-org |
| `SF_JWT_KEY_PROD` | mi-org | Private key (PEM) — **must be a different key from QAS's**, matching mi-org's own Connected App cert |
| `SF_USERNAME_PROD` | mi-org | `adminsalesforce@condor.com.py` |
| `SF_INSTANCE_URL_PROD` | mi-org | `https://condorsaci.my.salesforce.com` |

The `PROD` secrets are not yet set (see status below) — `deploy-prod.yml` will fail until they are.

## What each workflow does

- **`validate-pr.yml`** — on any PR targeting `main` or `production`: check-only deploy (`sf project deploy validate`) + runs the MGAgencia Apex test suite against `condor-qas`. Blocks nothing merging by itself (branch protection isn't wired to required status checks yet — see open items), but surfaces failures before merge.
- **`deploy-qas.yml`** — on push to `main`: real deploy to `condor-qas`, `RunSpecifiedTests` scoped to the MGAgencia test classes only.
- **`deploy-prod.yml`** — on push to `production`: real deploy to `mi-org`, same test scope, gated by the `production` Environment's required reviewer.

## Why `RunSpecifiedTests`, never `RunLocalTests`

`mi-org` (and `condor-qas`, to a lesser degree) has ~50 pre-existing test failures in classes unrelated to MGAgencia (Budget/Invoice/Account controllers, etc. — a known org-wide gap, not something this project owns). `RunLocalTests` runs every test in the org and fails the deploy on those unrelated failures. Every workflow here scopes tests explicitly to the 7 MGAgencia test classes. Confirmed the hard way on 2026-09-22: a `RunLocalTests` deploy reported 54 failures, none of them MGAgencia's.

## Status (2026-09-25)

- [x] `production` branch created, protected (no direct push, PR-only).
- [x] `production` GitHub Environment created, required reviewer configured, restricted to the protected branch.
- [x] `GitHub Actions Deploy` Connected App created and deployed to `condor-qas`.
- [x] QAS secrets set.
- [ ] `GitHub Actions Deploy` Connected App **not yet created in `mi-org`** — `deploy-prod.yml` will fail until this exists and the `_PROD` secrets are set.
- [ ] First real run of `validate-pr.yml` / `deploy-qas.yml` not yet verified end-to-end (JWT auth from the CI runner is untested — deliberately not tested from a local machine after an earlier JWT attempt disrupted the local `condor-qas` CLI session; the first real verification is this PR's own `validate-pr.yml` run).
