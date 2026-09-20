# Stardust 0.4.0

CLI control plane for Backdrop CMS. Apache + PHP + MariaDB + Bee + crdir.
No PHP panel.

This repository is **tools**, not a site. Do not `stardust platform-add stardust`.
Do not commit `/srv/platforms` or `/srv/stardust/state/secrets`.

## Layout

```
apps/                 one directory per app (host, apache, php, bee, …)
apps/MANIFEST         host-install order
install-stardust.sh   orchestrator — sources apps/<name>/install.sh
modules/              compatibility shims → apps/*/install.sh
bin/stardust          thin router (doctor, platform, site, bee, d7, …)
bin/stardust-priv     only root helper
lib/                  runtime libraries sourced by bin/stardust
docs/tutorial.txt     install + day-to-day
docs/d7-migration.txt Drupal 7 / BOA -> Backdrop
```

Work on one app at a time. Bee lives in `apps/bee/`
(`install.sh` for the host, `lib.sh` for `stardust bee PLATFORM PRODUCT …`).
Do not put Bee install logic back into `install-stardust.sh`.


## Roles and git branches

| Host role (`-m` / `STARDUST_ROLE`) | Default git branch |
|------------------------------------|--------------------|
| devel                              | `devel`            |
| test                               | `test`             |
| live                               | `live`             |

Override branch names in `/etc/stardust.conf` if the site repo uses other names:

```
BRANCH_DEVEL=main
BRANCH_TEST=staging
BRANCH_LIVE=production
# or pin this host: STARDUST_BRANCH=main
```

`platform-add` clones git when `STARDUST_GIT_TEMPLATE` or `--git` is set:

```
STARDUST_GIT_TEMPLATE=git@git.example:org/%s.git
stardust platform-add mysite
# same as: stardust platform-add mysite --git git@git.example:org/mysite.git
```

`--branch` always wins. Without a URL and without the template, Stardust falls back to `bee dl-core` and `git init`.

## Install

```sh
git clone -b devel git@git.example:org/stardust.git ~/stardust
cd ~/stardust
./install-stardust.sh -n --localhost    # laptop, 127.0.0.1
./install-stardust.sh -n -m devel       # devel workstation
./install-stardust.sh -n -m test        # remote test
./install-stardust.sh -n -F -m live     # remote live + CSF
```

Do not prefix the installer or `stardust` with `sudo`.
User binaries refuse root. Root work is `/usr/local/sbin/stardust-priv` only
(paths under `/srv/platforms` and `/srv/stardust`; DB names `bd_*`).

Site code is a **different** repository. Platforms live under `/srv/platforms`.
Promote (`stardust promote PLATFORM --to test|live`) runs on the test/live host, not on devel.
