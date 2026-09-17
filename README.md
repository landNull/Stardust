# Stardust 0.4.0

CLI control plane for Backdrop CMS. Apache + PHP + MariaDB + Bee + crdir.
No PHP panel.

This repository is **tools**, not a site. Do not `stardust platform-add stardust`.
Do not commit `/srv/platforms` or `/srv/stardust/state/secrets`.

## Layout

```
stardust-install.sh   host bootstrap (run from this directory)
bin/                  stardust, stardust-priv, stardust-menu, crdir, newfeature
lib/                  POSIX modules sourced by bin/stardust
man/                  stardust.1 crdir.1
docs/tutorial.txt     install + day-to-day
conf/                 reference settings JSON
tui/                  Bubble Tea source (optional; build with go)
```

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
./stardust-install.sh -n --localhost    # laptop, 127.0.0.1
./stardust-install.sh -n -m devel       # devel workstation
./stardust-install.sh -n -m test        # remote test
./stardust-install.sh -n -F -m live     # remote live + CSF
```

Do not prefix the installer or `stardust` with `sudo`.

Site code is a **different** repository. Platforms live under `/srv/platforms`.
Promote (`stardust promote PLATFORM --to test|live`) runs on the test/live host, not on devel.
