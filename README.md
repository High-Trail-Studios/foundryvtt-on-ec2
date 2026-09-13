# foundryvtt-on-ec2

Terraform to run [Foundry Virtual Tabletop](https://foundryvtt.com) on AWS for
game day, and switch it off the rest of the time.

> **Status: in development.** Nothing here is deployable yet. Sections are
> deliberately thin and will be rewritten as the implementation lands.

---

## What this is

A small, disposable Foundry server you start before a session and stop when you
are done. Your campaign lives on a persistent disk that survives the instance
being rebuilt, with backups to S3.

## What this is not

- **It does not include Foundry.** Foundry is commercial licensed software. You
  bring your own licence and your own download. We publish the infrastructure.
- **It is not a hosted service.** It runs in *your* AWS account, on your bill.
- **It is not highly available.** One instance, one availability zone. If the AZ
  fails, you restore from backup. That is the price of the cost profile.
- **It does not run 24/7.** It is designed to be stopped between sessions. If
  you want an always-on server, the economics here do not apply to you.

## Foundry version support

**v14 only** in this release. `docker/build.sh` refuses other major versions
rather than building something untested.

---

## Cost

Approximate, us-east-1, assuming ~12 hours of play per month and 30GB of data:

| | Monthly |
|---|---|
| Compute (t4g.medium, 12h) | ≈ $0.40 |
| EBS data volume (30GB, always on) | ≈ $2.40 |
| S3 backups (30GB) | ≈ $0.69 |
| Route 53 hosted zone | ≈ $0.50 |
| Public IPv4 (12h) | ≈ $0.06 |
| ECR image storage | ≈ $0.20 |
| **Total** | **≈ $4.25** |

Storage runs 24/7 and dominates. Compute barely registers — which is the whole
point of stopping the instance.

**Traps to know about:**

- **Leaving the instance running costs ~60x.** t4g.medium at 12h/month is
  ~$0.40; left on, ~$24. A scheduled nightly stop is included as a backstop,
  but stopping it yourself is the habit that matters.
- **No Elastic IP, deliberately.** AWS bills all public IPv4 at $0.005/hour
  since Feb 2024, including EIPs on stopped instances — ~$3.60/month for an
  address you use twelve hours. DNS is updated on boot instead.
- **EBS bills whether or not you play.** A month off still costs the volume.
- **Egress is not free.** Players downloading large maps pull data out of AWS
  at ~$0.09/GB. Modest for most tables; worth knowing if yours is asset-heavy.

---

## Prerequisites

Full list with rationale: **[REQUIREMENTS.md](REQUIREMENTS.md)**. The four that
stop people:

- **A Route 53 hosted zone, in this AWS account, with nameservers already
  delegated to it.** Not just owning a domain. TLS needs a real hostname, and
  the boot script rewrites an A record on every start. Delegating a single
  subdomain (`vtt.example.com`) is safer than moving a whole domain's DNS —
  see R1.
- **An AWS account you can create IAM roles in.** A restricted user fails at
  `terraform apply`.
- **A Foundry licence and the Linux/NodeJS download** — not the desktop app,
  not Foundry's own Docker build.
- **AWS CLI, Terraform, and Docker installed locally**, with `buildx` for the
  arm64 build.

---

## Setup

One time, in order. Step 3 must complete before step 6 or certificate issuance
fails.

### 1. Authenticate to AWS

TBD. Pick a region and stay in it — the data volume is pinned to one
availability zone.

### 2. Run Terraform

```bash
terraform init
terraform plan     # read this before applying
terraform apply
```

Creates: S3 backup bucket (versioned), ECR repository, persistent EBS data
volume, EC2 instance **in a stopped state**, security group, IAM instance role,
Route 53 record, budget and billing alarms.

Nothing bills meaningfully until you start the instance.

Outputs the ECR repository URL and the instance ID — both needed below.

### 3. Point DNS at the instance

TBD. Terraform manages the record; confirm it resolves before continuing.

### 4. Build and push the image

Download the Foundry Linux/NodeJS zip into `docker/`, then:

```bash
cd docker
./build.sh 14.364
# push to ECR — TBD
```

Builds for **arm64**, since the instance is Graviton. On an Intel machine this
runs under emulation and is slow.

### 5. Migrating an existing campaign? Upload it now

TBD. Upload your existing Foundry data directory to the S3 bucket **before
first start** — the instance seeds its data volume from S3 on boot. Doing this
after first start is the wrong order.

Skip if you are starting fresh.

### 6. Start the instance

TBD. First boot pulls the image, updates DNS, seeds data if present, and
obtains a certificate. Slower than subsequent boots.

### 7. Foundry first-run

TBD. Enter your licence key and set an admin password in the Foundry web UI.

---

## Every session

```bash
./foundry up      # TBD
./foundry down    # TBD — this is the one that keeps the bill near zero
```

---

## Backup and restore

TBD. Backup runs on instance stop, with Foundry shut down first so the world
database is consistent. Bucket versioning is on.

**Never copy a running Foundry world.** Foundry v14 stores worlds in LevelDB;
copying it while open produces a backup that appears fine and fails on restore.

---

## Updating Foundry

TBD. Build the new image, push, restart. Stays within v14 for this release.

---

## Teardown

TBD. Two stages, deliberately. The data volume is protected against accidental
destruction, so a clean teardown is: back up, verify the backup, then remove
the protection and destroy.

Verify afterwards that nothing is left billing — volume, snapshots, bucket,
ECR images.

---

## Design notes

Why it looks the way it does:

- **Instance disposable, data persistent.** The data volume has its own
  lifecycle, so the instance can be destroyed and rebuilt without risking the
  campaign.
- **EBS for live data, S3 for backup.** The live LevelDB needs a block device.
  EFS was rejected on cost and on NFS file-locking reliability.
- **No load balancer.** An ALB would cost ~$16/month to front a single
  instance. Caddy terminates TLS on the box.
- **No Elastic IP.** See the cost traps above.
- **Foundry's native S3 asset storage is not used.** It works, but Foundry
  requires the bucket to be public — anyone with a link can read your uploads.
  Documented as an opt-in, not a default.

## Limitations

- Single AZ. AZ failure means restore from backup, not automatic failover.
- Cold start is not instant. Start the instance a few minutes before players
  arrive.
- Route 53 only for DNS in v1.
- A certificate can expire if you go more than ~60 days without starting the
  instance. It re-issues on the next boot; the first start after a long gap is
  slower.

## Licence

TBD.
