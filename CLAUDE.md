# foundryvtt-on-ec2

Terraform to run Foundry Virtual Tabletop on EC2 for game day, stopped the rest
of the time.

<!-- Org philosophy loads automatically from the parent directory and is not
     repeated here. Keep this file to decisions, not description. -->

## Hard constraints

- **Foundry VTT is commercial licensed software. We never redistribute it.**
  No distribution zip, licence key, or Foundry binary in this repo or in any
  image we publish. The builder supplies their own copy at build time.
  `.gitignore` blocks `*.zip` — do not weaken it. Built images contain licensed
  software and belong in a private registry only.
- **Never copy a running Foundry world.** v14 stores worlds in LevelDB. Copying
  an open LevelDB yields a torn snapshot that looks fine and fails at restore.
  Any backup path must stop Foundry first. This applies to S3 sync, EBS
  snapshots, and everything else.
- **v14 only** this release. `docker/build.sh` refuses other major versions.

## Decisions already made — do not relitigate without cause

- **EBS for live data, S3 for seed and backup.** The live LevelDB needs a block
  device. EFS was rejected on cost (~13x S3) *and* on NFS file-locking
  reliability with LevelDB.
- **Data volume is separate from the instance**, with its own lifecycle and
  `prevent_destroy`. Instance stays disposable; the campaign does not.
- **No Elastic IP.** AWS bills all public IPv4 since Feb 2024, including EIPs on
  stopped instances — ~$3.60/mo, the largest line item in the stack. The boot
  script updates a Route 53 A record instead. TTL 60s, and DNS must be verified
  to resolve before Caddy starts or ACME burns its 5-failures-per-hour budget.
- **Caddy terminates TLS** in the compose stack. Its `/data` volume holds certs
  and must persist on the EBS volume — otherwise every boot re-requests a
  certificate and hits the 5-per-week duplicate limit.
- **No ALB** (~$16/mo to front one instance), **no ECS**.
- **Default t4g.medium**, document c7g.large. Both Graviton, so images must be
  built for arm64.
- **The instance builds its own image** (R13), natively on arm64, and only when
  the tag is absent from ECR — so the game-night path is always a plain pull.
  This is why Docker is not a user prerequisite, and why the instance role has
  ECR push. Do not move the build back to the user's machine without revisiting
  R12 and R14.
- **Foundry's native S3 asset storage is not used by default** — Foundry
  requires the bucket to be public. Opt-in only, with the caveat stated.

## Cost is the product

The pitch is "near-free for game day." At ~12h/month the bill is ~$4, and
storage dominates while compute is under a dollar. Leaving the instance running
costs ~60x. Treat any change that adds a standing hourly resource as a design
error until proven otherwise.

## Audience

Non-technical to lightly-technical adopters. Adoption friction is a bug. The
domain-name requirement is the hardest prerequisite and must stay stated up
front rather than discovered at first boot.

## Layout

- `docker/` — image build and compose stack (Foundry + Caddy)
- Terraform — TBD, not yet written

## Commands

TBD — no Terraform yet. `docker/build.sh <version>` builds locally for
development; it is not the deployment path (R13).
