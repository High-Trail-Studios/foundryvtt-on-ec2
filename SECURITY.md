# Security policy

## Reporting a vulnerability

Please report security issues **privately**, not in a public issue:
**[Report a vulnerability](https://github.com/High-Trail-Studios/foundryvtt-on-ec2/security/advisories/new)**
(the *Security* tab → *Report a vulnerability*).

Include what you found, how to reproduce it, and what an attacker could do with
it. If it involves a deployed stack, never include real account IDs, hostnames
or credentials — yours or anyone else's.

This is maintained by a small team on a best-effort basis. Expect an
acknowledgement within a week. There is no bug bounty.

## Scope

In scope — this repository's code and its defaults:

- IAM policies broader than the tool needs
- Anything that exposes the S3 bucket, ECR images, or instance to the internet
  beyond ports 80/443
- Secrets or licence material ending up somewhere readable (state, logs, images,
  S3 objects)
- The boot, backup and build scripts

Out of scope:

- **Foundry Virtual Tabletop itself.** Report those to Foundry Gaming via
  [foundryvtt.com](https://foundryvtt.com). It is their software; we only run
  it.
- AWS, Caddy, Docker or other upstream software — report to the upstream
  project.
- Risks already documented as limitations in the README, such as the stale DNS
  record between sessions, unless you have found a worse consequence than the
  one described.

## Supported versions

Only the latest release receives fixes. Pin to a release tag, and upgrade to
pick up security fixes.
