# Stardust milestones

Working tracker after the first successful live install on the Devuan VM
(`sd@devuan`, role=devel, `origin/devel` at `43e35a7`).

Host: starhq.knarr / VM hostname `devuan`
Repo: `github.com/landNull/Stardust` branch `devel`
Installer: `./install-stardust.sh -m devel` — completed through Bee.

---

## Milestone 0 — Doctor READY on the VM

The install finished. `stardust` is on PATH. Doctor is **NOT READY** because
this login shell still has the *pre-usermod* group set:

`sd cdrom floppy sudo audio dip video plugdev users netdev`

No `www-admin`, `stardust`, or `deploy`. That is why doctor also reports
`/srv/stardust/{backups,bin,state}` missing and `stardust-priv` missing —
those trees are `2770 deploy:www-admin` / `0750`. They exist; this shell
cannot see them.

- [ ] `exec su - sd` (not `exec bash`)
- [ ] `id` lists `www-admin` and `stardust` (and `deploy`)
- [ ] Confirm dirs as root if needed: `sudo ls -ld /srv/stardust /srv/stardust/backups /srv/stardust/bin /srv/stardust/state /usr/local/sbin/stardust-priv`
- [ ] `stardust doctor` prints **READY** (exit 0)
- [ ] `stardust list` / `stardust env` / `bee` (no args) work

Do **not** run `usermod` again unless `id` after `exec su -` still lacks
`www-admin`. The installer already added the groups.

---

## Milestone 1 — Install leftovers (devel, non-blocking)

Noise from the last run. None of these block doctor once groups refresh.

- [ ] Ignore `smartd failed` on the VM (no useful SMART devices)
- [ ] Ignore `mariadb not answering…` when the next line is `already running`
- [ ] Leave `/etc/stardust.conf` as-is unless `stardust env` shows a stale
      `ADMIN=www-admin` that doctor should treat as group-only (runtime already does)
- [ ] Optional: copy `/etc/msmtprc.example` → `/etc/msmtprc` only when NOTIFY= mail is wanted
- [ ] Optional: `stardust-tui` is absent until someone builds `tui/`
- [ ] Gitea skipped — set `STARDUST_GIT_TEMPLATE` when the forge exists

---

## Milestone 2 — Identity cleanup

Current policy (already in `devel`):

| Name | Role |
|---|---|
| `deploy` | system uid, nologin, locked. *This VM still has an older login-style deploy (`HOME=/home/deploy`).* |
| `www-admin` | file group only |
| `stardust` | secrets group |
| `sd` | temporary VM operator — groups only, never group `sudo` via the installer |
| `www-data` | daemon, also in `www-admin` |

- [ ] Decide: leave this VM’s `deploy` on `/home/deploy`, or convert
      (`usermod -d /srv/stardust/home -s /usr/sbin/nologin deploy` + move
      `.ssh` / `.gitconfig` / `.stardust.conf`). New hosts already get
      `/srv/stardust/home`.
- [ ] Align help text: `bin/stardust` still says `recommended: adm deploy`
      and the pre-doctor group warning still suggests `adm`. Drop `adm`
      from required/recommended to match the installer.
- [ ] Doctor should treat “cannot stat 2770 trees” as a group problem,
      not “dir missing”, so the next cold shell is less alarming.
- [ ] Confirm no user named `www-admin` exists (`getent passwd www-admin`).
      If the early workaround created one, `deluser www-admin` after
      checking it owns nothing.

---

## Milestone 3 — First platform on devel

Do this only after Milestone 0 is READY.

- [ ] Dry-run: `stardust -n platform-add scratch`
- [ ] Add a real platform (git URL when Gitea/template exists):
      `stardust -n platform-add mysite --git git@HOST:org/mysite.git --branch devel`
- [ ] `stardust inventory`
- [ ] Site: `stardust -n site-add mysite www --host www.devel --name "WWW devel"`
- [ ] Confirm Apache + PHP-FPM: vhost uses
      `SetHandler proxy:unix:/run/php/stardust-fpm.sock|fcgi://localhost/`
- [ ] `stardust site-check mysite www --host www.devel`
- [ ] `stardust bee mysite www status`
- [ ] `stardust site-backup mysite www`

---

## Milestone 4 — Git forge

STEP 60 skipped: no Gitea on this host.

- [ ] Decide where platforms live (Gitea on knarr, or GitHub `landNull`)
- [ ] Set `STARDUST_GIT_TEMPLATE` in `/etc/stardust.conf`
      (`git@HOST:org/%s.git`)
- [ ] Put deploy’s *outbound* forge key in the account’s HOME `.ssh`
      (this VM: `/home/deploy/.ssh` until Milestone 2 conversion)
- [ ] `sudo -u deploy git ls-remote` against one platform URL

---

## Milestone 5 — Promote path (test / live)

Not on this devel VM as a second environment. Separate host or a later
checkout under `/srv/platforms/mysite-test`.

- [ ] Install a test host with `./install-stardust.sh -n -m test` then without `-n`
- [ ] `-F` only after WireGuard SSH is proven
- [ ] `stardust -n promote mysite --to test` from the VPS checkout (ff-only)
- [ ] Same for live

---

## Milestone 6 — Docs and doctor copy-sync

- [ ] `docs/tutorial.txt` / `man/stardust.1` already describe group-only
      `www-admin` and system `deploy`. Re-read after Milestone 2 conversion.
- [ ] Keep this file current as tasks close.
- [ ] Hand-off stays: push files to `origin features/GrokBranch` when small;
      dated `GrokStardust-<sha>-<stamp>-MDT.bundle` only if a push would
      exceed the GitHub file-size limit; merge into `devel` on starhq.

---

## Closed on 2026-09-20

- [x] Dry-run vs live install (`-n` is preview only)
- [x] `www-admin` is a group, not a login
- [x] Invoking user gets `www-admin,stardust,deploy` only — never group `sudo`
- [x] System-account *policy* for `deploy` (this VM still has the old home)
- [x] Bee entry point `bee.php` on branch `1.x-1.x`
- [x] Idempotent `age-keygen` (`as_root test -f`)
- [x] `stardust` wrapper runs without `sudo`
- [x] `43e35a7` on `origin/devel` and `origin/features/GrokBranch`
