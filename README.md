# Stardust 0.3.0

CLI control plane for Backdrop CMS on starhq.knarr and the VPS.
Apache + PHP + MariaDB + Bee + crdir. No PHP panel.

This repo is **tools**, not a site. Do not `stardust platform-add stardust`.
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

## Gitea on knarr (localhost)

Create an empty repo `ORG/stardust` on Gitea. From this tree:

```sh
cd /path/to/stardust-repo
git init
git checkout -b devel
git add .
git status                          # no tui binary, no secrets
git commit -m "Stardust tools tree"
git remote add origin git@gitea-starhq:ORG/stardust.git
git push -u origin devel
```

Later:

```sh
git push origin devel
```

On another box:

```sh
git clone -b devel git@gitea-starhq:ORG/stardust.git ~/stardust
cd ~/stardust
./stardust-install.sh -n --localhost   # laptop
./stardust-install.sh -n -m devel      # knarr
```

Site code is a **different** repo (`ecom`, `torg`). Platforms live under `/srv/platforms`.

## Branches

| branch | machine |
|--------|---------|
| devel  | knarr / laptop |
| test   | VPS checkout ecom-test |
| live   | VPS checkout ecom-live |

Promote is `stardust promote PLATFORM --to test|live` on the VPS, not a merge in this tools repo.

## Do not commit

- `tui/stardust-tui` (built binary)
- passwords, `*.cnf`, restic keys
- `/etc/stardust.conf` from a live host
- platform checkouts
