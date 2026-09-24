# foundryvtt-on-ec2

Terraform to run [Foundry Virtual Tabletop](https://foundryvtt.com) on AWS for
game day, and switch it off the rest of the time.

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

**v14 only** in this release, tested on 14.368. Terraform and
`docker/build.sh` both refuse other major versions rather than build something
untested.

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

Full list with rationale: **[REQUIREMENTS.md](REQUIREMENTS.md)**. The ones
that stop people:

- **A Route 53 hosted zone, in this AWS account, with nameservers already
  delegated to it.** Not just owning a domain. TLS needs a real hostname, and
  the boot script rewrites an A record on every start. Delegating a single
  subdomain (`vtt.example.com`) is safer than moving a whole domain's DNS —
  see R1.
- **An AWS account you can create IAM roles in.** A restricted user fails at
  `terraform apply`.
- **A Foundry licence and the Node.js download.** Log in at
  [foundryvtt.com](https://foundryvtt.com), open your purchased licences, and
  on the download form pick:
  - **Version:** the same version you will set as `foundry_version` (default
    `14.368`). Only v14 is supported.
  - **Operating System: Node.js.** Not **Linux** — despite the name, that is
    the desktop app, and so are Windows and macOS. Not Foundry's Docker build
    either.

  You get `FoundryVTT-Node-<version>.zip`. Keep it; you upload it to AWS in
  step 4.
- **[AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
  and [Terraform](https://developer.hashicorp.com/terraform/install) 1.5+ or
  [OpenTofu](https://opentofu.org/docs/intro/install/) 1.6+ installed
  locally.** Tested with OpenTofu 1.12.6; with OpenTofu, type `tofu` wherever
  this README says `terraform`. Docker is *not* required — the instance builds its own
  image (R13). The
  [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
  is optional; it gives you a shell on the instance for troubleshooting.

---

## Setup

One time, in order. Run the `terraform` commands from the `terraform/`
directory.

### 1. Authenticate to AWS

Any method the AWS CLI supports works — `aws configure` for access keys, or
`aws sso login` if your organisation uses IAM Identity Center. Confirm you are
in the account that holds your Route 53 zone:

```bash
aws sts get-caller-identity
```

The region comes from `aws_region` in your tfvars, not from your CLI profile.
Pick one and stay in it — the data volume is pinned to one availability zone
there.

### 2. Run Terraform

Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`, then
edit it. Fill in every value in the `required` block and check `aws_region`.
Everything else has a working default; uncomment a line only to change it.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

terraform init
terraform plan     # read this before applying
terraform apply
```

Creates: S3 bucket (versioned, private, encrypted), ECR repository,
persistent EBS data volume, EC2 instance **in a stopped state**, VPC and
security group (unless you supplied your own), IAM roles, nightly auto-stop
schedule, budget and billing alarm. The DNS record is not created here — the
instance writes it on every start, because its address changes each time.

Nothing bills meaningfully until you start the instance. Storage does bill
from here on; see [Cost](#cost).

**Two emails need action:**

- **Confirm the SNS subscription** sent to `alert_email`. Until you do, the
  billing alarm has nowhere to deliver.
- The billing alarm also needs **billing alerts turned on for the account**,
  once: *Billing and Cost Management → Billing preferences → Alert
  preferences → Receive CloudWatch billing alerts*. Without it the alarm sits
  at "insufficient data" forever. The budget emails work either way.

### Keep your Terraform files safe

`terraform apply` leaves two files in `terraform/` that exist nowhere else:

- **`terraform.tfstate`** — Terraform's record of everything it created. Lose
  it and `terraform destroy` no longer knows what to remove: the resources keep
  billing until you find and delete each one by hand (they are all tagged
  `Project = <name_prefix>`, which helps). `terraform.tfstate.backup` is the
  previous version.
- **`terraform.tfvars`** — your settings. Easy to recreate, but annoying.

Both are gitignored here so they never land in a public fork. Copy them
somewhere durable and private after every `apply` — a private git repository,
a password manager, a private cloud drive. They hold your emails, hostname and
resource IDs, but no credentials.

**Not in this project's own S3 bucket:** teardown deletes that bucket, and the
state would go with it.

#### Optional: keep copies in a separate S3 bucket

One way to do it, if you want the copies in AWS. This is plain storage, not a
Terraform backend: Terraform keeps using the local files, and you push copies
after each `apply`. The bucket is created with the AWS CLI, not Terraform, so
teardown never touches it. Cost is a few cents a month.

Create it once, from `terraform/` (set `PREFIX` to your `name_prefix` so it
sits next to the project's bucket):

```bash
PREFIX=foundry
REGION=$(terraform output -raw region)
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
STATE_BUCKET="$PREFIX-tfstate-$ACCOUNT"

# us-east-1 must NOT be given a LocationConstraint; every other region must.
if [ "$REGION" = us-east-1 ]; then
  aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$REGION"
else
  aws s3api create-bucket --bucket "$STATE_BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi

aws s3api put-public-access-block --bucket "$STATE_BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Versioning keeps every earlier copy, so a bad push can be undone.
aws s3api put-bucket-versioning --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled
```

New S3 buckets are encrypted at rest by default.

**Push** after every `apply`:

```bash
for f in terraform.tfstate terraform.tfstate.backup terraform.tfvars; do
  aws s3 cp "$f" "s3://$STATE_BUCKET/$f"
done
```

**Pull** onto a new machine, into a fresh clone's `terraform/` directory, then
run `terraform init`:

```bash
for f in terraform.tfstate terraform.tfstate.backup terraform.tfvars; do
  aws s3 cp "s3://$STATE_BUCKET/$f" "$f"
done
```

Limits: there is no locking, so run Terraform from one machine at a time, and
the bucket is only as current as your last push. After a full teardown the
state is empty and the bucket has done its job — empty and delete it in the S3
console (*Empty*, then *Delete*; the CLI's `rb --force` cannot remove the old
versions).

### 3. Check DNS delegation

The instance updates your hostname on every start, but only works if the
internet already asks Route 53 about it. Check the zone's nameservers:

```bash
dig NS vtt.example.com +short     # use your zone name
```

You should see four `awsdns` servers, matching the NS record in your Route 53
zone. If you see your registrar's servers, or nothing, delegation is not done —
fix that first (REQUIREMENTS.md R1). Starting with broken delegation fails
safely: the boot script refuses to request a certificate until DNS resolves,
but Foundry will not come up either.

### 4. Upload the Foundry download to S3

Copy the exact destination from the `foundry_zip_destination` Terraform
output. Upload *to that name* even if your downloaded file is called something
else — the instance looks for exactly that name.

```bash
terraform output -raw foundry_zip_destination
aws s3 cp ~/Downloads/<your-download>.zip "$(terraform output -raw foundry_zip_destination)"
```

That is the whole step. The instance builds the image itself on first start —
natively on arm64, no Docker needed on your machine.

### 5. Migrating an existing campaign? Upload it now

Skip if you are starting fresh.

Upload your existing Foundry **user data folder** — the one that contains
`Config/` and `Data/` — to the bucket's `backup/` prefix **before first
start**. On boot the instance copies `backup/` onto its data volume, but only
while that volume is empty. After first start it is no longer empty, and the
upload is ignored.

**Close Foundry completely first.** Worlds are LevelDB databases; copying one
while Foundry has it open produces a copy that looks fine and fails to load.

Default locations of the user data folder (yours may differ — Foundry's
*Configuration* tab shows it as *User Data Path*):

| OS      | Path                                          |
|---------|-----------------------------------------------|
| Windows | `%LOCALAPPDATA%\FoundryVTT`                   |
| macOS   | `~/Library/Application Support/FoundryVTT`    |
| Linux   | `~/.local/share/FoundryVTT`                   |

```bash
BUCKET=$(terraform output -raw bucket)

aws s3 sync "PATH/TO/FoundryVTT" "s3://$BUCKET/backup/" \
  --exclude "Logs/*" \
  --exclude "Config/options.json"
```

For example, on macOS:

```bash
aws s3 sync "$HOME/Library/Application Support/FoundryVTT" "s3://$BUCKET/backup/" \
  --exclude "Logs/*" --exclude "Config/options.json"
```

`options.json` is excluded because it holds your local machine's settings
(port, SSL certificate paths, UPnP), which are wrong on the server; Foundry
recreates it with defaults. `Config/license.json` *is* uploaded, so you will
not need to re-enter your licence key. The bucket is private and encrypted.

Check the layout — you should see `backup/Config/` and `backup/Data/`, not
`backup/FoundryVTT/`:

```bash
aws s3 ls "s3://$BUCKET/backup/"
```

### 6. Start the instance

```bash
$(terraform output -raw start_command)
```

On every start the instance, in order: points your hostname at its new IP and
waits until that resolves, pulls the Foundry image from ECR (or builds it —
see below), seeds the data volume from `backup/` if the volume is empty, and
starts Foundry behind Caddy, which obtains a TLS certificate.

**First start takes several minutes longer** because the instance builds the
image from your zip and pushes it to ECR. That happens once per Foundry
version, not once per session. Every later start is a plain pull, a couple of
minutes end to end.

Then open `terraform output -raw url`.

### 7. Foundry first-run

**Do this immediately.** Until an admin password is set, Foundry's setup screen
is open to anyone who finds your URL.

1. Accept the licence agreement and enter your licence key (skipped if you
   migrated a campaign — it came with `Config/license.json`).
2. **Set an administrator password** under *Configuration*.
3. Create or launch a world and invite your players with the URL above.

---

## Every session

From the `terraform/` directory:

```bash
$(terraform output -raw start_command)   # a few minutes before players arrive
$(terraform output -raw stop_command)    # afterwards — this is what keeps the bill near zero
```

The commands are plain AWS CLI calls; `terraform output` prints them if you
would rather save them somewhere. Stopping also takes the backup (below).

**Auto-stop backstop:** the instance is stopped every day at 08:00 UTC whether
or not you remembered. Late sessions in the Americas can run into this —
change `auto_stop_cron`, or disable it with `enable_auto_stop = false` if you
accept the risk.

---

## Backup and restore

**Backup** runs on every stop, including the auto-stop: Foundry is shut down
first, then the data folder is synced to `s3://<bucket>/backup/`. Bucket
versioning keeps previous versions for 30 days, so a bad session can be rolled
back.

**Never copy a running Foundry world.** Foundry v14 stores worlds in LevelDB;
copying it while open produces a backup that appears fine and fails on restore.
The backup never does this, and neither should you.

What the backup does not cover:

- **It only runs on a clean stop.** A hardware failure or forced stop skips it;
  you fall back to the previous session's backup.
- **EC2 does not wait forever for a shutdown.** Syncs are incremental, so this
  only matters for the first backup of a large campaign. After uploading many
  gigabytes of assets, check that `backup/` looks complete.
- **Caddy's certificates are not backed up.** They live on the data volume and
  are simply re-issued if lost.

**Restore** is the migration path in step 5: the instance seeds from
`backup/` whenever its data volume is empty. To roll back to an earlier
version, restore the objects you want in S3 (the console's *Show versions*
view), then give the instance an empty data volume.

To take a copy of your campaign off AWS:

```bash
aws s3 sync "s3://$(terraform output -raw bucket)/backup/" ./foundry-backup/
```

---

## Updating Foundry

Within v14 only for this release. With the instance stopped:

1. Download the new Node.js zip (see [Prerequisites](#prerequisites)).
2. Set `foundry_version` in `terraform.tfvars` and run `terraform apply`. This
   updates config in S3; it does not touch the instance.
3. Upload the zip to the new `foundry_zip_destination` (step 4).
4. Start the instance. It builds the new version once, as on first start.

The previous version's image stays in ECR (the three most recent are kept), so
rolling back is setting `foundry_version` back and applying. Foundry may
migrate your worlds' data on first launch of a new version, and that does not
roll back — stop cleanly on the old version first, so a backup exists.

---

## Teardown

Two stages, deliberately. The data volume is protected against accidental
destruction, so a plain `terraform destroy` stops at it with an error. That is
the design working.

1. **Stop the instance** so a final backup is taken, then copy it somewhere
   you control (the `aws s3 sync` command above). Check the copy.
2. **Remove the protections:**
   - In `terraform/storage.tf`, change `prevent_destroy = true` to `false`.
   - In `terraform.tfvars`, set `s3_force_destroy = true` and
     `ecr_force_delete = true`.
   - Run `terraform apply` so the new settings take effect.
3. **`terraform destroy`.** This deletes the bucket *including every backup*,
   the ECR images, and the data volume.
4. **Delete the DNS record by hand.** The instance created it, not Terraform,
   so destroy leaves it behind. Remove the A record for your hostname in the
   Route 53 console. Leaving it points your hostname at an IP address AWS will
   give to someone else.
5. **Delete the hosted zone** if you created it only for this — it costs
   $0.50/month on its own.

Then check nothing is left billing: in the EC2 console, *Volumes* and
*Snapshots*; in S3, the bucket; in ECR, the repository.

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
  Assets live on the data volume instead. You can configure it yourself in
  Foundry against a separate, public bucket; this project does not.

## Limitations

- Single AZ. AZ failure means restore from backup, not automatic failover.
- Cold start is not instant. Start the instance a few minutes before players
  arrive.
- Route 53 only for DNS in v1.
- Graviton (arm64) only. Instance types must be `t4g`, `c7g` or similar.
- **Between sessions, your hostname points at a stale IP.** The address is
  released when the instance stops and AWS may reassign it. Anyone reaching
  your hostname then lands on whoever holds that IP now. Low risk for a game
  server, but worth knowing.
- Certificates are short-lived, and Caddy renews them only while running. After
  a long break the first start re-issues one and takes a little longer.

## Troubleshooting

Foundry not reachable a few minutes after start? Read the boot log — no shell
access needed:

```bash
aws ec2 get-console-output --region "$(terraform output -raw region)" --instance-id "$(terraform output -raw instance_id)" --latest --output text
```

Look for lines starting `[bootstrap]` and `[boot]`; the last one before an
`ERROR` says what failed. The common causes:

| Symptom in the log | Cause |
|---|---|
| `DNS still resolves to …` | Delegation is not working — see step 3. |
| `…zip not found` | The zip is missing or misnamed — see step 4. |
| `no public IPv4` | Your own subnet does not auto-assign public IPs. |

With the Session Manager plugin you can get a shell instead —
`$(terraform output -raw logs_command)` — and follow the boot live with
`journalctl -u foundry-boot -f`, or check the containers with
`sudo docker compose -f /opt/foundry/docker-compose.yml ps`.

## Licence

[MIT](LICENSE) — covers this repository's code and documentation only.
Foundry Virtual Tabletop is commercial software under its own licence, is not
included here, and is not covered by this one. Images you build contain it:
keep them in a private registry.
