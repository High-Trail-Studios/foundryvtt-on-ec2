# foundryvtt-on-ec2

Terraform to run Foundry Virtual Tabletop on EC2.

<!-- Scaffold. Org philosophy loads automatically from the parent directory and
     is not repeated here. Fill in Stack and Commands once code exists. -->

## Design constraints

- **Foundry VTT is commercial licensed software. We do not redistribute it.**
  What we publish is the infrastructure to run it; the adopter brings their own
  licence and supplies their own download credentials at deploy time. No
  licence key, no distribution URL, no Foundry binary in this repo or in any
  image we publish.
- **Game data is the pet; the instance is not.** Worlds, modules, and uploaded
  assets are the one thing here that cannot be rebuilt from code. Persist them
  off the instance root volume and say plainly in the README what a rebuild
  does and does not preserve.
- **Usage is bursty and scheduled** — a game night, then nothing for days.
  Anything that bills per hour runs 24/7 for a few hours of actual use. Prefer
  a design that can be stopped between sessions, and name the tradeoff.
- No ALB. A single instance behind a stable address is the right size for this.

## Out of scope (v1)

- Multi-world orchestration, autoscaling, managed backups-as-a-service. One
  instance, one Foundry, clean teardown.

## Stack

TBD — no code yet. (Foundry is a Node application; deployment shape not yet
decided.)

## Commands

TBD — no build, test, or deploy commands yet.

## Note

`README.md` currently says `foundryvtt-in-aws`, which does not match the repo
name. Worth reconciling before the repo goes public.
