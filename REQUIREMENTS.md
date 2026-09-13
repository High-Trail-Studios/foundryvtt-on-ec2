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
> project claims a non-technical audience. Either the docs walk through
> delegation carefully, or we accept that the audience is "lightly technical."
> Unresolved — see R14.

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

- ECR: pull the image
- S3: read/write the backup bucket only
- Route 53: `ChangeResourceRecordSets` on the one hosted zone only

Per org policy the actual policy is part of the product and goes in the README.

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

### R12 — AWS CLI, Terraform, Docker — **User**

Docker needs `buildx` for the arm64 cross-build. Local disk: ~250MB for the
zip, 1–2GB for the built image.

### R13 — arm64 build capability — **User/Design** — **Open**

Building a Graviton image on an Intel machine works under emulation but is
slow, and it is the step most likely to strand a non-technical user.

Open alternative: have the instance build the image natively on first boot from
a zip in S3, which removes Docker from the prerequisite list entirely. Costs a
slower first boot and more boot-script complexity. **Not yet decided.**

---

## Open questions

### R14 — Who is the actual audience?

R1 and R13 both push toward "lightly technical" rather than "non-technical."
Worth settling explicitly, because it decides how much the docs carry and how
much we automate away.

### R15 — Teardown versus `prevent_destroy`

The data volume is protected against accidental deletion, which breaks a plain
`terraform destroy`. Clean teardown is mandatory per org policy. Current plan
is a deliberate two-stage path: back up, verify, unprotect, destroy.

### R16 — DNS provider seam

v1 is Route 53 only. DNS provider is a variable target and belongs behind a
seam so other providers are additions rather than rewrites. Not built in v1.
