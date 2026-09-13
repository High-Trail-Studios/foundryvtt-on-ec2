# Requirements

Numbered so they can be referenced from tickets, commits, and the README.
This file is the source of truth; the README's prerequisites section is the
friendly subset and links here.

**Status: draft.** Expect churn while the design settles.

| Tag | Meaning |
| --- | --- |
| **User** | The adopter must provide or do this before setup |
| **Design** | A constraint on how we build, not something the user supplies |
| **Open** | Not yet decided |

---

## Domain and DNS

### R1 — Route 53 hosted zone, delegated — **User**

A hosted zone in Route 53, **in the same AWS account**, serving a domain or
subdomain whose nameservers are already delegated to it. Not merely "owns a
domain."

This is the hardest prerequisite in the project and the most likely reason
someone bounces off. It is required because:

- TLS needs a real hostname; Let's Encrypt will not issue for a bare IP.
- We dropped the Elastic IP on cost, so the public address changes on every
  start and the boot script has to rewrite an A record. That needs API access
  to the zone.

**Recommended path: delegate a subdomain, not the whole domain.** Create a
hosted zone for `vtt.example.com` in Route 53, then add an `NS` record for
`vtt` at the existing DNS provider pointing at that zone's four nameservers.
Email, the main website, and every other record stay untouched. Moving a whole
domain's DNS to Route 53 risks breaking MX records and is not worth it here.

> **Honest tension:** NS delegation is not a non-technical task, and this
> project claims a non-technical audience. Since R13 was resolved, this is the
> *only* remaining obstacle to that claim — see R14.

### R2 — Ports 80 and 443 reachable from the internet — **User**

80 for the ACME HTTP challenge and the HTTPS redirect, 443 for play. Players
must be able to reach the host too.

---

## AWS

### R3 — AWS account with elevated permissions — **User**

Terraform creates IAM roles and policies, which a restricted IAM user cannot
do. A locked-down day-to-day user will fail at `apply`.

### R4 — Region with Graviton availability — **User/Design**

t4g/c7g are not in every region or every AZ. Region choice is also sticky: the
EBS data volume is pinned to one AZ and the instance must launch there.

### R5 — Billing guardrails before anything bills — **Design**

Budget and CloudWatch billing alarm, created and verified before the first
billable resource. Same rule as ChronKeeper. The failure mode here is a
forgotten running instance, not overspending.

### R6 — Least-privilege instance role, documented — **Design**

The instance needs exactly:

- ECR: pull **and push**, scoped to the one repository (see R13)
- S3: read/write the backup bucket only
- Route 53: `ChangeResourceRecordSets` on the one hosted zone only

Per org policy the actual policy is part of the product and goes in the README.

> **Accepted tradeoff:** push access means a compromised instance could poison
> its own image. Low concern for this threat model, but it is a real widening
> and the reason is R13. If it ever stops being acceptable, moving the build to
> CodeBuild returns the instance to pull-only.

### R7 — No standing hourly resources — **Design**

No NAT gateway, no ALB, no Elastic IP. Any addition that bills by the hour
while nobody is playing is a design error until argued otherwise.

### R8 — SSM Session Manager for access, not SSH — **Design** — **Open**

Avoids an open port 22 and key management. Needs confirming that it works
cleanly without a NAT gateway in a public subnet.

---

## Foundry

### R9 — Foundry licence — **User**

A licence permits one active instance. Running this and a home server
simultaneously is not allowed by Foundry's terms.

### R10 — The correct download — **User**

The **Linux/NodeJS** package, not the Windows/macOS app and not Foundry's own
Docker distribution. Downloading the wrong one is a common failure.

### R11 — v14 only — **Design**

`docker/build.sh` refuses other major versions. Revisit per release.

---

## Local tooling

### R12 — AWS CLI and Terraform — **User**

Docker is **not** required locally; see R13. Local disk: ~250MB for the Foundry
zip, which is uploaded to S3 rather than built against.

### R13 — Image is built on the instance — **Design** — *decided*

The instance builds its own image, natively on arm64, **only when the tag is
absent from ECR**:

```
if ECR has foundryvtt:$VERSION   -> pull
else                             -> fetch zip from S3, build, push to ECR
```

So the game-night path is always a plain pull. The build runs once per Foundry
version, during setup, when nobody is waiting to play — which is what makes a
build step in user-data acceptable at all.

Chosen because it removes Docker, `buildx` and QEMU emulation from the user's
prerequisites entirely (R12). Rejected alternatives: building on the user's
laptop (kept Docker as a hard prerequisite and meant a 5–10 minute emulated
build for Intel and Windows users); CodeBuild (cleaner separation and keeps the
instance pull-only, but adds a service and a worse debugging story).

Consequences:

- Instance role gains ECR push — see R6.
- Root volume needs ~4GB of working headroom for the build.
- The Dockerfile, compose file and Caddyfile must reach the instance. Intended
  approach is Terraform-managed `aws_s3_object`s pulled at boot, so they are
  versioned with the infrastructure and changeable without an image rebuild.
  **Implementation detail, not yet settled.**
- `docker/build.sh` remains for local development and testing, but is no longer
  the primary path.

---

## Open questions

### R14 — Who is the actual audience?

R13 is resolved in the direction that removes technical burden, so **R1 is now
the only hard obstacle left**: NS delegation is not something a non-technical
user does unaided.

That narrows the question usefully. Either the docs walk through delegation
step by step and we claim non-technical honestly, or we accept "lightly
technical" and stop apologising for it. Still worth deciding explicitly,
because it governs how much the docs carry.

### R15 — Teardown versus `prevent_destroy`

The data volume is protected against accidental deletion, which breaks a plain
`terraform destroy`. Clean teardown is mandatory per org policy. Current plan
is a deliberate two-stage path: back up, verify, unprotect, destroy.

### R16 — DNS provider seam

v1 is Route 53 only. DNS provider is a variable target and belongs behind a
seam so other providers are additions rather than rewrites. Not built in v1.
