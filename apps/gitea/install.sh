#!/bin/sh
# apps/gitea/install.sh — optional Gitea forge + STARDUST_GIT_TEMPLATE
# Sourced by install-stardust.sh (STEP 60).
#
# Do not wget https://gitea.com (that is the marketing homepage, not a binary).
# Do not rewrite an existing /etc/gitea/app.ini.
# Binary comes from dl.gitea.com (GitHub releases as fallback) and is checksummed.

echo "STEP 60: Gitea (optional git forge)"

# Unix account that runs the Gitea *process*. Same style as deploy:
# system uid, nologin, locked password, home = work dir (not /home/git).
# git@ in clone URLs is SSH_USER in app.ini — not a Linux login
# (same idea as git@github.com). That needs Gitea's own SSH listener;
# OpenSSH-as-git would require a login shell, which we will not give.
GITEA_USER=git
GITEA_HOME=/var/lib/gitea
GITEA_SSH_USER=git

# --- helpers (defined here so an older orchestrator still works) ------------

gitea_conf_path() {
  for f in \
    /etc/gitea/app.ini \
    /var/lib/gitea/custom/conf/app.ini \
    /etc/gitea/conf/app.ini \
    /home/git/gitea/custom/conf/app.ini
  do
    if [ -f "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

gitea_bin_path() {
  # A runnable gitea binary. PATH last — "have gitea" can be a wrapper.
  for b in /usr/local/bin/gitea /usr/bin/gitea /home/git/gitea/gitea; do
    if [ -x "$b" ]; then
      printf '%s\n' "$b"
      return 0
    fi
  done
  if have gitea; then
    command -v gitea
    return 0
  fi
  return 1
}

gitea_installed() {
  # Binary present = installed. app.ini alone is leftover config, not an install.
  gitea_bin_path >/dev/null
}

gitea_report_status() {
  # Always print what we found. Return 0 only when a binary exists.
  bin=$(gitea_bin_path || true)
  gc=$(gitea_conf_path || true)
  if [ -n "$bin" ]; then
    echo "Gitea binary: $bin"
    if [ -n "$gc" ]; then
      echo "Gitea config: $gc (will not rewrite)"
    else
      echo "Gitea config: none yet (app.ini will be written on install)"
    fi
    return 0
  fi
  if [ -n "$gc" ]; then
    echo "Gitea not installed: no binary (looked in /usr/local/bin /usr/bin PATH)"
    echo "Gitea leftover config: $gc (will not rewrite if you say Y)"
    return 1
  fi
  echo "Gitea not installed: no binary, no app.ini"
  echo "  looked for: /usr/local/bin/gitea, /usr/bin/gitea, gitea on PATH,"
  echo "              /etc/gitea/app.ini and the other usual conf paths"
  return 1
}

gitea_can_prompt() {
  # Keyboard available? Theia / sudo / piped stdin often fail [ -t 0 ]
  # even though /dev/tty is the terminal you are looking at.
  [ -t 0 ] && return 0
  [ -e /dev/tty ] && [ -r /dev/tty ] && [ -w /dev/tty ] && return 0
  return 1
}

gitea_read_line() {
  # Set ans from the keyboard. Prefer a real stdin TTY; else /dev/tty.
  ans=
  if [ -t 0 ]; then
    IFS= read -r ans || ans=
    return 0
  fi
  if [ -r /dev/tty ]; then
    IFS= read -r ans </dev/tty || ans=
    return 0
  fi
  return 1
}

gitea_stty() {
  if [ -t 0 ]; then
    stty "$@" 2>/dev/null || true
    return 0
  fi
  if [ -e /dev/tty ]; then
    stty "$@" </dev/tty 2>/dev/null || true
  fi
}

stardust_git_configured() {
  for f in "${HOME:-}/.stardust.conf" /etc/stardust.conf; do
    [ -f "$f" ] || continue
    val=$(sed -n 's/^STARDUST_GIT_TEMPLATE=//p' "$f" | tail -n 1)
    case $val in
      ''|*YOURORG*|*git.example*) ;;
      *) return 0 ;;
    esac
  done
  return 1
}

gitea_help_show() {
  # Always write to the terminal. Never stdout: gitea_ask is captured with $().
  text=$1
  if [ -z "$text" ]; then
    printf '%s\n' "(no extra help for this question)" >&2
    return 0
  fi
  text="${text}

----
Type q to close this help and return to the question.
Press Enter at the prompt to keep the default in [brackets]."
  dest=/dev/stderr
  if printf '' >/dev/tty 2>/dev/null; then
    dest=/dev/tty
  fi
  pager=""
  if command -v sensible-pager >/dev/null 2>&1; then
    pager=sensible-pager
  elif command -v less >/dev/null 2>&1; then
    pager="less -F -X -E"
  elif command -v more >/dev/null 2>&1; then
    pager=more
  fi
  if [ -n "$pager" ]; then
    printf '%s\n' "$text" | $pager >"$dest" 2>/dev/null || printf '%s\n' "$text" >&2
  else
    printf '%s\n' "$text" >&2
    printf 'Press Enter to continue... ' >&2
    gitea_read_line || true
  fi
}

gitea_ask() {
  # gitea_ask "Question" "default" "long help" "needed: one-line what to type"
  # Prints the question, then the needed line, then > [default]:
  # Type ? or help for the long new-sysadmin help. Empty keeps the default.
  q=$1
  def=${2:-}
  help=${3:-}
  needed=${4:-}
  while :; do
    if [ -n "$help" ]; then
      printf '%s  (? help)\n' "$q" >&2
    else
      printf '%s\n' "$q" >&2
    fi
    if [ -n "$needed" ]; then
      printf '%s\n' "$needed" >&2
    fi
    if [ -n "$def" ]; then
      printf '> [%s]: ' "$def" >&2
    else
      printf '> ' >&2
    fi
    gitea_read_line || ans=
    case $ans in
      \?|help|HELP)
        gitea_help_show "$help"
        continue
        ;;
    esac
    [ -n "$ans" ] || ans=$def
    printf '%s\n' "$ans"
    return 0
  done
}

gitea_ask_secret() {
  # gitea_ask_secret "Question" "long help" "needed line"
  # Does not echo. Empty means "generate one".
  q=$1
  help=${2:-}
  needed=${3:-}
  while :; do
    if [ -n "$help" ]; then
      printf '%s  (? help)\n' "$q" >&2
    else
      printf '%s\n' "$q" >&2
    fi
    if [ -n "$needed" ]; then
      printf '%s\n' "$needed" >&2
    fi
    printf '> (hidden, empty = generate): ' >&2
    if command -v stty >/dev/null 2>&1; then
      gitea_stty -echo
    fi
    gitea_read_line || ans=
    if command -v stty >/dev/null 2>&1; then
      gitea_stty echo
    fi
    printf '\n' >&2
    case $ans in
      \?|help|HELP)
        gitea_help_show "$help"
        continue
        ;;
    esac
    printf '%s\n' "$ans"
    return 0
  done
}

gitea_prompt_intro() {
  [ "${GITEA_INTRO_SHOWN:-0}" -eq 1 ] && return 0
  GITEA_INTRO_SHOWN=1
  printf '%s\n' \
    "Each Gitea question shows what is needed in one line. Type ? or help" \
    "for a longer explanation with examples (q closes the pager). Enter = default." >&2
}

gitea_env() {
  # gitea_env NAME — print $NAME if set, else empty. POSIX, no nameref.
  eval "printf '%s\\n' \"\${$1:-}\""
}

gitea_yes() {
  case $1 in Y|y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

gitea_arch() {
  m=$(uname -m 2>/dev/null || echo x86_64)
  case $m in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    i386|i686|i586) echo 386 ;;
    armv7*|armv6*) echo arm-6 ;;
    armv5*) echo arm-5 ;;
    *) echo amd64 ;;
  esac
}

gitea_default_domain() {
  if [ "${LOCALHOST:-0}" -eq 1 ]; then
    printf '%s\n' "git.devel"
    return 0
  fi
  fqdn=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "")
  case $fqdn in
    git.*) printf '%s\n' "$fqdn" ;;
    *.*)   printf '%s\n' "git.$fqdn" ;;
    *)     printf '%s\n' "git.starhq.knarr" ;;
  esac
}

gitea_default_ssh_host() {
  if [ -f "${HOME:-}/.ssh/config" ]; then
    h=$(awk 'tolower($1)=="host" && $2 !~ /[*?]/ {
      if ($2 ~ /gitea|github|gitlab|git/) { print $2; exit }
    }' "$HOME/.ssh/config" 2>/dev/null || true)
    if [ -n "$h" ]; then
      printf '%s\n' "$h"
      return 0
    fi
  fi
  printf '%s\n' "gitea-starhq"
}

gitea_rand() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 18 2>/dev/null | tr -d '/+=\n' | cut -c1-20
  elif [ -r /dev/urandom ]; then
    dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' | cut -c1-20
  else
    printf 'chg-%s\n' "$$$(date +%s)"
  fi
}

gitea_secret() {
  kind=$1
  if [ -x /usr/local/bin/gitea ]; then
    val=$(/usr/local/bin/gitea generate secret "$kind" 2>/dev/null || true)
    if [ -n "$val" ]; then
      printf '%s\n' "$val"
      return 0
    fi
  fi
  gitea_rand
}

gitea_fetch() {
  # gitea_fetch URL DEST — curl preferred, wget fallback. No root needed.
  url=$1
  dest=$2
  if have curl; then
    curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
    return $?
  fi
  if have wget; then
    wget -q -O "$dest" "$url"
    return $?
  fi
  echo "$PROG: need curl or wget to download Gitea" >&2
  return 1
}

gitea_verify_sha256() {
  bin=$1
  sumfile=$2
  [ -f "$bin" ] && [ -f "$sumfile" ] || return 1
  want=$(awk '{print $1; exit}' "$sumfile")
  [ -n "$want" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$bin" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    got=$(shasum -a 256 "$bin" | awk '{print $1}')
  elif command -v openssl >/dev/null 2>&1; then
    got=$(openssl dgst -sha256 "$bin" | awk '{print $NF}')
  else
    echo "note: no sha256 tool; skipping checksum (install coreutils)"
    return 0
  fi
  if [ "$want" = "$got" ]; then
    echo "gitea: sha256 ok"
    return 0
  fi
  echo "$PROG: Gitea checksum mismatch (want $want got $got)" >&2
  return 1
}

# --- help texts (new sysadmin; opened with ? or help) ----------------------

GITEA_HELP_INSTALL='Install Gitea on THIS machine?

Gitea is a self-hosted Git forge — like a private GitHub. Stardust
clones Backdrop platforms from it:

  git@gitea-starhq:myorg/ecom.git
  → /srv/platforms/ecom

WHEN TO SAY YES (Y)
  • This box is the devel host (starhq / knarr / a laptop with --localhost)
    and you do not already have a forge.
  • You want platform-add to clone from a URL you control, not from
    GitHub, and not from a fresh "bee dl-core" tree.

WHEN TO SAY NO (n)
  • Gitea already runs somewhere else (another VM, a NAS, GitHub).
  • This is a test/live VPS — those hosts CLONE from the forge; they
    should not RUN the forge.
  • You are not ready; you can re-run install-stardust.sh later. This
    step is optional and will not undo Apache/PHP/MariaDB/Bee.

EXAMPLES
  sd@devuan (devel VM):     Y
  laptop  --localhost:      Y   (Gitea on 127.0.0.1, browse git.devel)
  VPS  -m test / -m live:   n   (point STARDUST_GIT_TEMPLATE at the forge)
  already have GitHub:      n   (template git@github.com:landNull/%s.git)

What this step will do if you say Y
  1. Create system user "git" (nologin, locked, home /var/lib/gitea)
     the same way Stardust creates "deploy". No /home/git, no login shell.
     git@ in clone URLs is SSH_USER in app.ini; sshd never logs this user in.
  2. Download the official Gitea *binary* from dl.gitea.com
     (never the gitea.com homepage HTML) and verify its sha256.
  3. Write /etc/gitea/app.ini ONLY if that file does not exist.
  4. Install a sysvinit script (or systemd/openrc if that is init).
  5. Optionally put Apache in front so you browse http://HOSTNAME/
     instead of :3000.
  6. Start Gitea'\''s own SSH on 2222 (OpenSSH on 22 stays for humans).
  7. Ask for the Git owner/org and SSH host alias, then write
     STARDUST_GIT_TEMPLATE in /etc/stardust.conf.


Re-running is safe. An existing app.ini is never rewritten.'

GITEA_HELP_DOMAIN='Public hostname for the forge

This is the name people (and git) use to reach Gitea. It becomes:

  DOMAIN and SSH_DOMAIN in app.ini
  ROOT_URL = http://HOSTNAME/     (if Apache is in front)
  ROOT_URL = http://HOSTNAME:3000/ (if you talk to Gitea directly)

It does NOT have to match `hostname`. It DOES have to resolve on
the machines that will clone — devel, laptop, and later the VPS.

HOW RESOLUTION WORKS IN STARDUST
  --localhost
      dnsmasq already maps *.devel → 127.0.0.1
      so git.devel works in a browser on this laptop.

  devel host
      dnsmasq maps *.devel → the host LAN/WG address.
      git.devel is the usual pick. If you have real DNS
      (git.starhq.knarr), use that instead.

  test/live
      use a public name you already created in DNS, e.g. git.example.com.
      You still need HTTP 80 (Apache) or 3000 open; SSH stays WG/LAN.

EXAMPLES
  git.devel              laptop / devel, uses dnsmasq
  git.starhq.knarr       LAN name for the devel VM
  git.example.com        public VPS with a DNS A record

Put the name in /etc/hosts on any box that does not use dnsmasq:

  192.168.1.120  git.starhq.knarr
  10.8.0.1       git.starhq.knarr

Wrong: an IP as the hostname (git URLs become ugly and certs will fail).
Wrong: github.com — that is not *your* forge; skip this install instead.'

GITEA_HELP_PROXY='Put Apache in front of Gitea? (reverse proxy)

Gitea itself listens on TCP 3000. Apache can accept HTTP on port 80
and forward it, so you type http://git.devel/ instead of :3000.

SAY YES (Y) — default, recommended
  • You already have Apache from STEP 20.
  • Port 80 is what CSF leaves open (devel: 80; test/live: 80+443).
  • Browsers, bookmarks, and ROOT_URL stay clean.
  • Gitea binds 127.0.0.1:3000 so the forge is not on the public NIC.

  We write /etc/apache2/sites-available/stardust-gitea.conf
  (only if it is absent), a2enmod proxy proxy_http, a2ensite,
  then reload Apache.

SAY NO (n)
  • You will browse http://HOSTNAME:3000/ yourself.
  • On a VPS you must open TCP 3000 in CSF — Stardust does not.
  • Fine on a laptop if you do not want another vhost.

EXAMPLES
  Y  http://git.devel/            (Apache → 127.0.0.1:3000)
  n  http://127.0.0.1:3000/       (Gitea exposed directly)

HTTPS / certbot is a later step on test/live, not during this install.
After a cert exists, set ROOT_URL to https://HOSTNAME/ in app.ini
and restart Gitea — we will not touch an existing app.ini to do that.'

GITEA_HELP_SSH='How git clone/push talks to the forge

Unix user "git" is the application account (like deploy):
  system uid, nologin, locked password, HOME=/var/lib/gitea.
  No /home/git. You never get a shell as git.

git@ in clone URLs is SSH_USER in app.ini — the same trick GitHub
uses (git@github.com is not a Linux login). It happens to match
the Unix name. sshd on port 22 never logs this user in.

Gitea listens for git SSH itself (default port 2222). OpenSSH on
port 22 stays for humans. That is what lets the git account stay
nologin: sshd never runs a shell as git.

  Host gitea-starhq
    HostName git.starhq.knarr
    User git
    Port 2222
    IdentityFile /srv/stardust/home/.ssh/id_ed25519
    IdentitiesOnly yes

  git@gitea-starhq:myorg/ecom.git

CSF on a VPS does not open 2222 for you. Allow it from WireGuard
10.8.0.0/24 and LAN only — same as you already do for 22.

Do not pick "system" / OpenSSH-as-git. That would need a login
shell on the forge account (sshd runs command= through the shell).
We will not give git a shell.

EXAMPLES
  devel VM / laptop:     gitea   (port 2222, Host alias sets Port)
  VPS that clones here:  gitea   (open 2222 on WG/LAN in CSF)

Type gitea. "system" is accepted but switched to gitea so the
account stays nologin like deploy.'

GITEA_HELP_DB='Where Gitea stores users, issues, and repo metadata

This is Gitea'\''s own database, not a Backdrop site DB. Site DBs stay
bd_<product>_<role> via stardust-priv. Do not reuse those names.

sqlite3  (default) — one file, no extra accounts
  Path: /var/lib/gitea/data/gitea.db
  The Gitea binary already contains SQLite. Fine for a devel forge,
  a laptop, and small teams. Backup = copy that file (or gitea dump).
  You do not need the sqlite3 package.

mysql — MariaDB on this host (STEP 40 already installed it)
  We create database "gitea" and user gitea@localhost with a random
  password, as root over the unix socket. The password goes into
  /etc/gitea/app.ini and /srv/stardust/state/secrets/gitea.cnf
  (mode 0640, group stardust).

  Pick mysql if you already know you will have many repos / users,
  or you want the forge metadata inside the same MariaDB you back up.

EXAMPLES
  first forge on a devel VM:     sqlite3
  laptop --localhost:            sqlite3
  busy team, MariaDB already
  tuned with 2G buffer pool:     mysql

Type sqlite3 or mysql. Other values fall back to sqlite3.
PostgreSQL is not offered here (Stardust does not ship Postgres).'

GITEA_HELP_ADMIN='First Gitea administrator

Gitea will refuse a useful login until an admin user exists. This is
a Gitea login, NOT a Linux login. It is not "deploy" and it is not
"www-admin" (www-admin is a group).

USERNAME
  Pick something you will type in the browser. Letters, digits,
  hyphen. "sd" is fine if that is your Linux operator; "admin" is
  fine too. Do not use "deploy" — that name is reserved in your
  head for the system account that runs git/bee.

EMAIL
  Gitea wants an email on the account. It does not have to be a
  real mailbox unless you later enable the mailer. Example:
  sd@starhq.knarr

PASSWORD
  The next question (hidden). Empty = we generate one, print it
  once, and also write it under /srv/stardust/state/secrets/.
  Change it in the Gitea UI after the first login.

After install, sign in at ROOT_URL, then:
  • Site Administration → Identity & access → Organizations
    create the org you will put in STARDUST_GIT_TEMPLATE
  • Your Settings → SSH / GPG Keys → add YOUR laptop key
  • Add deploy'\''s public key (we print it at the end) as a
    deploy key on the org, or as a user key on a "deploy" Gitea
    user. deploy must be able to git ls-remote as itself.'

GITEA_HELP_ADMIN_PASS='Password for the Gitea admin user

This is typed at the Gitea web login, not at a Linux prompt.

EXAMPLES
  Type a password you will remember — it will not echo.
  Press Enter on an empty line — Stardust generates a 20-character
    random password, prints it ONCE, and stores a copy in
    /srv/stardust/state/secrets/gitea-admin.txt (0640 deploy:stardust).

Do not reuse the Linux password for sd/root. Do not put this
password in app.ini (Gitea hashes it into its database).

If you lose it and have no mailer:

  sudo -u git GITEA_WORK_DIR=/var/lib/gitea \\
    /usr/local/bin/gitea admin user change-password \\
    --config /etc/gitea/app.ini --username YOURUSER --password NEW'

GITEA_HELP_OWNER='Git owner / organization

This is the first path component after the colon in an SSH URL:

  git@HOST:OWNER/ecom.git
                 ^^^^^ this

On Gitea it is either:
  • an Organization you will create in the UI (recommended for a
    team — ecom, torg, stardust all live under one org), or
  • your Gitea username (fine for a one-person devel box).

On GitHub it is landNull or another org. You can point the
template at GitHub without installing Gitea — say n to "Install
Gitea" and still fill this in.

EXAMPLES
  myorg          →  git@gitea-starhq:myorg/ecom.git
  sd             →  git@gitea-starhq:sd/ecom.git
  landNull       →  git@github.com:landNull/ecom.git

Stardust substitutes the platform name for %s:

  STARDUST_GIT_TEMPLATE=git@gitea-starhq:myorg/%s.git
  stardust platform-add ecom
    clones git@gitea-starhq:myorg/ecom.git

The org does not have to exist yet. Create it in the Gitea UI
after this installer finishes, then create empty private repos
named after each platform (ecom, torg, stardust, …).

Empty answer: skip the template. platform-add will fall back to
bee dl-core + git init until you set STARDUST_GIT_TEMPLATE in
/etc/stardust.conf by hand.'

GITEA_HELP_SSH_HOST='Git SSH host alias

This is the HOST in git@HOST:org/repo.git — usually a Host line in
SSH config, NOT necessarily public DNS.

Why an alias?
  git@git.starhq.knarr:myorg/ecom.git  works only if:
    • that name resolves, AND
    • your SSH key is offered, AND
    • (for built-in SSH) you remember Port 2222.
  An alias pins all of that in one place:

    Host gitea-starhq
      HostName git.starhq.knarr    # or 127.0.0.1 on --localhost
      User git
      IdentityFile /srv/stardust/home/.ssh/id_ed25519
      IdentitiesOnly yes
      # Port 2222                  # only if you chose "gitea" SSH

  Then the URL is always git@gitea-starhq:myorg/ecom.git
  and STARDUST_GIT_TEMPLATE=git@gitea-starhq:myorg/%s.git

EXAMPLES
  gitea-starhq     Stardust default, scanned from ~/.ssh/config
  git.devel        fine if that name already resolves and you
                   do not need extra SSH options
  github.com       if the forge is GitHub, not Gitea
  127.0.0.1        last resort on a laptop; ugly URLs

We write /etc/ssh/ssh_config.d/50-stardust-gitea.conf when that
directory exists, so sudo -u deploy git ls-remote works without
a per-user config. We do not overwrite an existing file.

Empty host: skip the template.'

GITEA_HELP_VERSION='Gitea version to download

A three-part version from https://dl.gitea.com/gitea/  (the binary
CDN). Do not paste a URL. Do not type "latest".

  1.27.3     current documented stable when this module was written
  1.27.1     also fine
  1.22.6     old; only if you already standardised on it

The file we fetch is:

  https://dl.gitea.com/gitea/VERSION/gitea-VERSION-linux-ARCH
  https://dl.gitea.com/gitea/VERSION/gitea-VERSION-linux-ARCH.sha256

GitHub is the fallback if the CDN fails:

  https://github.com/go-gitea/gitea/releases/download/vVERSION/...

ARCH is detected from uname -m (amd64, arm64, 386, arm-6).

Leave the default unless you know you need another version.
Upgrading later is: stop gitea, replace /usr/local/bin/gitea with
the same filename, start gitea. Do not rename the binary.'

GITEA_HELP_ADMIN_EMAIL='Email address on the Gitea admin user

Gitea stores an email on every account. It is NOT used to send mail
unless you later turn on [mailer] in app.ini (Stardust leaves the
mailer off).

EXAMPLES
  sd@starhq.knarr     matches the devel operator
  sd@git.devel        fine on --localhost; need not exist in DNS
  you@example.com     if you will enable the mailer later

Wrong: leaving it empty — Gitea admin user create wants an address.
Wrong: a Linux system user name with no @.

Forgot it? Change it in the Gitea UI after login:
  Your Settings → Account → Email addresses.'

GITEA_HELP_SSH_PORT='Port for Gitea'\''s built-in SSH server

Gitea listens for git clone/push itself so the Unix account "git"
can stay nologin (like deploy). OpenSSH on 22 is not used for git.

  2222     usual pick (does not fight with OpenSSH)
  22       only if OpenSSH is not using 22 on this host

URLs Gitea prints look like:

  ssh://git@HOSTNAME:2222/myorg/ecom.git

The Host alias we write hides the port:

  Host gitea-starhq
    HostName git.starhq.knarr
    User git
    Port 2222
    IdentityFile /srv/stardust/home/.ssh/id_ed25519
    IdentitiesOnly yes

  git@gitea-starhq:myorg/ecom.git     still works (alias sets Port)

"User git" here is SSH_USER, not a Linux account.

On a VPS with CSF you must allow TCP 2222 yourself (WG/LAN only).
Stardust does not open it. On --localhost nothing extra is needed.

Leave 2222 unless you already standardised on another port.'


# --- save template ---------------------------------------------------------

gitea_save_template() {
  host=$1
  owner=$2
  if [ -z "$host" ] || [ -z "$owner" ]; then
    echo "no owner/host — leave STARDUST_GIT_TEMPLATE empty"
    return 0
  fi
  tpl="git@${host}:${owner}/%s.git"
  dest=/etc/stardust.conf
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ STARDUST_GIT_TEMPLATE=$tpl -> $dest"
    return 0
  fi
  if [ -f "$dest" ] && grep -q '^STARDUST_GIT_TEMPLATE=' "$dest"; then
    as_root sed -i "s|^STARDUST_GIT_TEMPLATE=.*|STARDUST_GIT_TEMPLATE=$tpl|" "$dest"
  elif [ -f "$dest" ]; then
    as_root sh -c "printf 'STARDUST_GIT_TEMPLATE=%s\\n' '$tpl' >> '$dest'"
  else
    echo "note: $dest missing — write STARDUST_GIT_TEMPLATE=$tpl by hand"
    return 0
  fi
  echo "wrote STARDUST_GIT_TEMPLATE=$tpl"
}

gitea_prompt_git_template() {
  if stardust_git_configured; then
    echo "git template already set — skip STARDUST_GIT_TEMPLATE prompt"
    return 0
  fi
  env_host=$(gitea_env GITEA_SSH_HOST)
  env_owner=$(gitea_env GITEA_OWNER)
  if [ -n "$env_host" ] && [ -n "$env_owner" ]; then
    gitea_save_template "$env_host" "$env_owner"
    return 0
  fi
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ prompt STARDUST_GIT_TEMPLATE (host + owner/org)"
    return 0
  fi
  if ! gitea_can_prompt; then
    echo "no keyboard — not prompting for git template (set STARDUST_GIT_TEMPLATE in /etc/stardust.conf)"
    return 0
  fi
  host_def=${env_host:-$(gitea_default_ssh_host)}
  gitea_prompt_intro
  echo "Empty host or empty owner skips the clone template."
  if [ -z "$env_host" ]; then
    host=$(gitea_ask "Git SSH host alias — HOST in git@HOST:org/repo.git" "$host_def" "$GITEA_HELP_SSH_HOST" \
      "Needed: the HOST in git@HOST:org/repo.git — usually an SSH alias like gitea-starhq.")
  else
    host=$env_host
  fi
  if [ -z "$host" ]; then
    echo "no host — leave STARDUST_GIT_TEMPLATE empty"
    return 0
  fi
  if [ -z "$env_owner" ]; then
    owner=$(gitea_ask "Git owner/org — first path after the colon" "" "$GITEA_HELP_OWNER" \
      "Needed: the org or username after the colon (myorg in git@HOST:myorg/ecom.git). Empty skips.")
  else
    owner=$env_owner
  fi
  gitea_save_template "$host" "$owner"
}

# keep the old name so a caller of maybe_gitea_defaults still works
maybe_gitea_defaults() {
  gitea_prompt_git_template
}

# --- install pieces --------------------------------------------------------

gitea_nologin_shell() {
  if type nologin_shell >/dev/null 2>&1; then
    nologin_shell
    return 0
  fi
  for s in /usr/sbin/nologin /sbin/nologin /usr/bin/nologin; do
    [ -x "$s" ] && { echo "$s"; return 0; }
  done
  echo /usr/sbin/nologin
}

gitea_ensure_user() {
  # Same method as ensure_owner (deploy): system uid, nologin, locked,
  # home = $GITEA_HOME. Never /home/git, never a login shell.
  user=$GITEA_USER
  home=$GITEA_HOME
  shell=$(gitea_nologin_shell)
  if id gitea >/dev/null 2>&1; then
    echo "note: leftover Unix user gitea exists — Gitea runs as $user, not gitea"
  fi
  if id "$user" >/dev/null 2>&1; then
    echo "user ok: $user (existing; not rewriting shell or home)"
    return 0
  fi
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ mkdir -p $home"
    echo "+ adduser --system --home $home --shell $shell --disabled-password --group $user"
    echo "+ passwd -l $user"
    return 0
  fi
  adduser_bin=$(find_admin_bin adduser || true)
  useradd_bin=$(find_admin_bin useradd || true)
  groupadd_bin=$(find_admin_bin groupadd || true)
  passwd_bin=$(find_admin_bin passwd || true)
  run_root mkdir -p "$home"
  if [ -n "$adduser_bin" ] && [ "${PKG:-}" = apt ]; then
    run_root "$adduser_bin" --system --home "$home" --shell "$shell" \
      --disabled-password --group --gecos "Git Version Control" "$user" || {
      echo "$PROG: could not create system user $user" >&2
      return 1
    }
  else
    if [ -n "$groupadd_bin" ] && ! getent group "$user" >/dev/null 2>&1; then
      run_root "$groupadd_bin" --system "$user" 2>/dev/null || run_root "$groupadd_bin" "$user" || true
    fi
    if [ -n "$useradd_bin" ]; then
      run_root "$useradd_bin" -r -M -d "$home" -s "$shell" -g "$user" \
        -c "Git Version Control" "$user" || {
        echo "$PROG: could not create system user $user" >&2
        return 1
      }
    else
      echo "$PROG: no useradd/adduser to create $user" >&2
      return 1
    fi
  fi
  if [ -n "$passwd_bin" ]; then
    run_root "$passwd_bin" -l "$user" 2>/dev/null || true
  fi
  echo "system user: $user home=$home shell=$shell (locked, like deploy)"
}

gitea_ensure_dirs() {
  user=$GITEA_USER
  home=$GITEA_HOME
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ mkdir $home/{custom,data,log} /etc/gitea  (no /home/git)"
    return 0
  fi
  run_root mkdir -p "$home/custom" "$home/data" "$home/log"
  run_root mkdir -p /etc/gitea
  run_root chown -R "$user:$user" "$home"
  run_root chmod -R 750 "$home"
  run_root chown "root:$user" /etc/gitea
  run_root chmod 770 /etc/gitea
}

gitea_download() {
  ver=$1
  arch=$2
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ fetch https://dl.gitea.com/gitea/${ver}/gitea-${ver}-linux-${arch}"
    echo "+ sha256 verify, install /usr/local/bin/gitea"
    return 0
  fi
  if [ -x /usr/local/bin/gitea ]; then
    echo "gitea binary exists: /usr/local/bin/gitea (not re-downloaded)"
    return 0
  fi
  work=$(mktemp -d)
  bin="$work/gitea"
  sum="$work/gitea.sha256"
  name="gitea-${ver}-linux-${arch}"
  url1="https://dl.gitea.com/gitea/${ver}/${name}"
  url2="https://github.com/go-gitea/gitea/releases/download/v${ver}/${name}"
  echo "gitea: downloading $name"
  if gitea_fetch "$url1" "$bin"; then
    gitea_fetch "${url1}.sha256" "$sum" || true
  elif gitea_fetch "$url2" "$bin"; then
    echo "gitea: used GitHub releases fallback"
    gitea_fetch "${url2}.sha256" "$sum" || true
  else
    echo "$PROG: could not download Gitea $ver ($arch) from dl.gitea.com or GitHub" >&2
    echo "$PROG: not fetching the Gitea homepage — pick a version from https://dl.gitea.com/gitea/" >&2
    rm -rf "$work"
    return 1
  fi
  if [ -s "$sum" ]; then
    if ! gitea_verify_sha256 "$bin" "$sum"; then
      rm -rf "$work"
      return 1
    fi
  else
    echo "note: no sha256 file; installing without checksum"
  fi
  run_root install -m 0755 "$bin" /usr/local/bin/gitea
  rm -rf "$work"
  echo "installed /usr/local/bin/gitea"
}

gitea_write_app_ini() {
  domain=$1
  http_addr=$2
  http_port=$3
  root_url=$4
  ssh_port=$5
  start_ssh=$6
  db_type=$7
  db_pass=$8
  def_branch=$9

  dest=/etc/gitea/app.ini
  if [ -f "$dest" ]; then
    echo "exists: $dest (unchanged — will not rewrite app.ini)"
    return 0
  fi
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ write $dest (INSTALL_LOCK=true, DB_TYPE=$db_type, ROOT_URL=$root_url)"
    return 0
  fi

  secret=$(gitea_secret SECRET_KEY)
  token=$(gitea_secret INTERNAL_TOKEN)
  jwt=$(gitea_secret JWT_SECRET)

  db_block="DB_TYPE = sqlite3
PATH = /var/lib/gitea/data/gitea.db
"
  if [ "$db_type" = mysql ]; then
    db_block="DB_TYPE = mysql
HOST = 127.0.0.1:3306
NAME = gitea
USER = gitea
PASSWD = ${db_pass}
SSL_MODE = disable
CHARSET = utf8mb4
"
  fi

  proxy_block=""
  if [ "$http_addr" = "127.0.0.1" ]; then
    proxy_block="REVERSE_PROXY_LIMIT = 1
REVERSE_PROXY_TRUSTED_PROXIES = 127.0.0.0/8,::1/128
"
  fi

  tmp=$(mktemp)
  cat >"$tmp" <<EOF
; Stardust-generated Gitea config. Re-install will not overwrite this file.
APP_NAME = Stardust Gitea
RUN_USER = $GITEA_USER
RUN_MODE = prod
WORK_PATH = $GITEA_HOME

[repository]
ROOT = /var/lib/gitea/data/gitea-repositories
DEFAULT_BRANCH = $def_branch

[server]
APP_DATA_PATH = /var/lib/gitea/data
PROTOCOL = http
DOMAIN = $domain
SSH_DOMAIN = $domain
HTTP_ADDR = $http_addr
HTTP_PORT = $http_port
ROOT_URL = $root_url
DISABLE_SSH = false
START_SSH_SERVER = $start_ssh
SSH_USER = $GITEA_SSH_USER
SSH_PORT = $ssh_port
SSH_LISTEN_HOST = ${ssh_listen:-0.0.0.0}
SSH_LISTEN_PORT = $ssh_port
LFS_START_SERVER = true
LFS_JWT_SECRET = $jwt
OFFLINE_MODE = false
${proxy_block}
[database]
$db_block
[security]
INSTALL_LOCK = true
SECRET_KEY = $secret
INTERNAL_TOKEN = $token
PASSWORD_HASH_ALGO = pbkdf2

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = false
DEFAULT_KEEP_EMAIL_PRIVATE = true
ENABLE_NOTIFY_MAIL = false

[mailer]
ENABLED = false

[log]
MODE = file
LEVEL = info
ROOT_PATH = /var/lib/gitea/log

[actions]
ENABLED = false

[lfs]
PATH = /var/lib/gitea/data/lfs
EOF
  as_root install -m 0640 "$tmp" "$dest"
  rm -f "$tmp"
  as_root chown "root:$GITEA_USER" "$dest"
  as_root chmod 640 "$dest"
  as_root chmod 750 /etc/gitea
  echo "wrote $dest (not world-readable; not rewritten on later runs)"
}

gitea_mysql() {
  pass=$1
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ mysql CREATE DATABASE gitea / USER gitea@localhost"
    return 0
  fi
  cli=mysql
  have mysql || cli=mariadb
  if ! have mysql && ! have mariadb; then
    echo "note: no mysql client; cannot create Gitea DB" >&2
    return 1
  fi
  if ! as_root "$cli" -N -e "SELECT 1" >/dev/null 2>&1; then
    echo "note: MariaDB not answering; start it, then re-run" >&2
    return 1
  fi
  as_root "$cli" -e "CREATE DATABASE IF NOT EXISTS gitea CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
  # IDENTIFIED BY on CREATE USER — isolated so a rerun does not trip set -eu
  as_root "$cli" -e "CREATE USER IF NOT EXISTS 'gitea'@'localhost' IDENTIFIED BY '${pass}'" >/dev/null 2>&1 || \
    as_root "$cli" -e "CREATE USER 'gitea'@'localhost' IDENTIFIED BY '${pass}'" >/dev/null 2>&1 || true
  as_root "$cli" -e "CREATE USER IF NOT EXISTS 'gitea'@'127.0.0.1' IDENTIFIED BY '${pass}'" >/dev/null 2>&1 || \
    as_root "$cli" -e "CREATE USER 'gitea'@'127.0.0.1' IDENTIFIED BY '${pass}'" >/dev/null 2>&1 || true
  as_root "$cli" -e "GRANT ALL PRIVILEGES ON gitea.* TO 'gitea'@'localhost'"
  as_root "$cli" -e "GRANT ALL PRIVILEGES ON gitea.* TO 'gitea'@'127.0.0.1'" >/dev/null 2>&1 || true
  as_root "$cli" -e "FLUSH PRIVILEGES"
  echo "mariadb: database gitea + user gitea@localhost"
  sec=${STARDUST:-/srv/stardust}/state/secrets/gitea.cnf
  if [ ! -f "$sec" ]; then
    tmp=$(mktemp)
    printf '%s\n' "[client]" "user=gitea" "password=${pass}" "host=127.0.0.1" >"$tmp"
    as_root install -m 0640 "$tmp" "$sec"
    rm -f "$tmp"
    as_root chown "${OWNER:-deploy}:stardust" "$sec" 2>/dev/null || true
    echo "wrote $sec"
  fi
}

gitea_write_init() {
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ init script for gitea (INIT=${INIT:-unknown})"
    return 0
  fi
  case ${INIT:-unknown} in
    systemd)
      dest=/etc/systemd/system/gitea.service
      if [ -f "$dest" ]; then
        echo "exists: $dest (unchanged)"
        return 0
      fi
      tmp=$(mktemp)
      cat >"$tmp" <<'EOF'
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target

[Service]
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/var/lib/gitea GITEA_WORK_DIR=/var/lib/gitea

[Install]
WantedBy=multi-user.target
EOF
      as_root install -m 0644 "$tmp" "$dest"
      rm -f "$tmp"
      as_root systemctl daemon-reload 2>/dev/null || true
      echo "wrote $dest"
      ;;
    openrc)
      dest=/etc/init.d/gitea
      if [ -f "$dest" ]; then
        echo "exists: $dest (unchanged)"
        return 0
      fi
      tmp=$(mktemp)
      cat >"$tmp" <<'EOF'
#!/sbin/openrc-run
name="gitea"
command="/usr/local/bin/gitea"
command_args="web --config /etc/gitea/app.ini"
command_user="git:git"
directory="/var/lib/gitea"
command_background=true
pidfile="/run/gitea.pid"
export USER=git
export HOME=/var/lib/gitea
export GITEA_WORK_DIR=/var/lib/gitea
EOF
      as_root install -m 0755 "$tmp" "$dest"
      rm -f "$tmp"
      echo "wrote $dest"
      ;;
    sysv|unknown|*)
      dest=/etc/init.d/gitea
      if [ -f "$dest" ]; then
        echo "exists: $dest (unchanged)"
        return 0
      fi
      tmp=$(mktemp)
      cat >"$tmp" <<'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          gitea
# Required-Start:    $network $remote_fs $syslog
# Required-Stop:     $network $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Gitea (Git with a cup of tea)
# Description:       Self-hosted Git service for Stardust
### END INIT INFO

GITEA_USER="git"
GITEA_BIN="/usr/local/bin/gitea"
GITEA_WORK_DIR="/var/lib/gitea"
GITEA_CONFIG="/etc/gitea/app.ini"
PIDFILE="/var/run/gitea.pid"
export USER=git
export HOME=/var/lib/gitea
export GITEA_WORK_DIR=/var/lib/gitea

if [ -f /lib/lsb/init-functions ]; then
  # shellcheck disable=SC1091
  . /lib/lsb/init-functions
fi

do_start() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    return 0
  fi
  if command -v start-stop-daemon >/dev/null 2>&1; then
    start-stop-daemon --start --quiet --background --make-pidfile --pidfile "$PIDFILE" \
      --chuid "$GITEA_USER" --chdir "$GITEA_WORK_DIR" \
      --exec "$GITEA_BIN" -- web --config "$GITEA_CONFIG"
    return $?
  fi
  su -s /bin/sh -c "cd '$GITEA_WORK_DIR' && exec '$GITEA_BIN' web --config '$GITEA_CONFIG'" "$GITEA_USER" \
    >/var/lib/gitea/log/gitea-daemon.log 2>&1 &
  echo $! >"$PIDFILE"
}

do_stop() {
  if command -v start-stop-daemon >/dev/null 2>&1; then
    start-stop-daemon --stop --quiet --pidfile "$PIDFILE" --exec "$GITEA_BIN" 2>/dev/null || true
  elif [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
  fi
  rm -f "$PIDFILE"
}

case "$1" in
  start) do_start ;;
  stop) do_stop ;;
  restart) do_stop; sleep 1; do_start ;;
  status)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "gitea is running"
      exit 0
    fi
    echo "gitea is not running"
    exit 3
    ;;
  *)
    echo "Usage: /etc/init.d/gitea {start|stop|restart|status}"
    exit 1
    ;;
esac
exit 0
EOF
      as_root install -m 0755 "$tmp" "$dest"
      rm -f "$tmp"
      if have update-rc.d; then
        run_root update-rc.d gitea defaults >/dev/null 2>&1 || true
      fi
      echo "wrote $dest"
      ;;
  esac
}

gitea_write_apache() {
  domain=$1
  http_port=$2
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ Apache vhost stardust-gitea ServerName $domain → 127.0.0.1:$http_port"
    return 0
  fi
  if [ ! -d /etc/apache2/sites-available ]; then
    echo "note: no /etc/apache2/sites-available — proxy $domain to 127.0.0.1:$http_port by hand"
    return 0
  fi
  if have a2enmod; then
    run_root a2enmod proxy >/dev/null 2>&1 || true
    run_root a2enmod proxy_http >/dev/null 2>&1 || true
    run_root a2enmod headers >/dev/null 2>&1 || true
  fi
  dest=/etc/apache2/sites-available/stardust-gitea.conf
  if [ -f "$dest" ]; then
    echo "exists: $dest (unchanged)"
  else
    tmp=$(mktemp)
    cat >"$tmp" <<EOF
# Stardust — Gitea reverse proxy. Re-install will not overwrite this file.
<VirtualHost *:80>
  ServerName $domain
  ProxyPreserveHost On
  ProxyRequests Off
  AllowEncodedSlashes NoDecode
  RequestHeader set X-Forwarded-Proto "http"
  ProxyPass / http://127.0.0.1:${http_port}/ nocanon
  ProxyPassReverse / http://127.0.0.1:${http_port}/
</VirtualHost>
EOF
    as_root install -m 0644 "$tmp" "$dest"
    rm -f "$tmp"
    echo "wrote $dest"
  fi
  if have a2ensite; then
    run_root a2ensite stardust-gitea.conf >/dev/null 2>&1 || true
  fi
  if [ -n "${RELOAD_APACHE:-}" ]; then
    run_root sh -c "$RELOAD_APACHE" || true
  elif [ -x /etc/init.d/apache2 ]; then
    run_root /etc/init.d/apache2 reload || true
  fi
}

gitea_write_ssh_config() {
  alias=$1
  hostname=$2
  ssh_port=$3
  ident=$4
  if [ -z "$alias" ] || [ -z "$hostname" ]; then
    return 0
  fi
  body="Host $alias
  HostName $hostname
  User $GITEA_SSH_USER
  IdentitiesOnly yes
"
  if [ -n "$ident" ]; then
    body="${body}  IdentityFile $ident
"
  fi
  if [ "$ssh_port" != "22" ]; then
    body="${body}  Port $ssh_port
"
  fi
  dest=/etc/ssh/ssh_config.d/50-stardust-gitea.conf
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ write $dest (Host $alias → $hostname port $ssh_port)"
    return 0
  fi
  if [ -d /etc/ssh/ssh_config.d ]; then
    if [ -f "$dest" ]; then
      echo "exists: $dest (unchanged)"
    else
      printf '%s\n' "$body" | write_dropin "$dest"
    fi
  else
    snippet=${STARDUST:-/srv/stardust}/state/ssh-gitea.conf
    if [ ! -f "$snippet" ]; then
      if [ "${DRYRUN:-0}" -eq 0 ]; then
        as_root mkdir -p "$(dirname "$snippet")"
        tmp=$(mktemp)
        printf '%s\n' "$body" >"$tmp"
        as_root install -m 0644 "$tmp" "$snippet"
        rm -f "$tmp"
      fi
    fi
    echo "note: no /etc/ssh/ssh_config.d — snippet at $snippet (copy into ~/.ssh/config)"
  fi
}

gitea_ensure_deploy_key() {
  home=$(getent passwd "${OWNER:-deploy}" 2>/dev/null | cut -d: -f6)
  [ -n "$home" ] || home=${STARDUST:-/srv/stardust}/home
  key=$home/.ssh/id_ed25519
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ ssh-keygen -t ed25519 -f $key (if absent) as ${OWNER:-deploy}" >&2
    printf '%s\n' "$key"
    return 0
  fi
  run_root mkdir -p "$home/.ssh"
  run_root chown "${OWNER:-deploy}:${OWNER:-deploy}" "$home/.ssh" 2>/dev/null || true
  run_root chmod 700 "$home/.ssh"
  if [ ! -f "$key" ]; then
    if command -v ssh-keygen >/dev/null 2>&1; then
      as_root -u "${OWNER:-deploy}" ssh-keygen -t ed25519 -f "$key" -N "" -C "${OWNER:-deploy}@$(hostname)" || \
        as_root ssh-keygen -t ed25519 -f "$key" -N "" -C "${OWNER:-deploy}@$(hostname)" || true
      as_root chown "${OWNER:-deploy}:${OWNER:-deploy}" "$key" "$key.pub" 2>/dev/null || true
      as_root chmod 600 "$key" 2>/dev/null || true
      echo "deploy key: $key" >&2
    else
      echo "note: ssh-keygen missing — create $key by hand" >&2
    fi
  else
    echo "deploy key exists: $key" >&2
  fi
  printf '%s\n' "$key"
}

gitea_create_admin() {
  user=$1
  email=$2
  pass=$3
  if [ -z "$user" ] || [ -z "$pass" ]; then
    echo "note: skip Gitea admin user (need username + password)"
    return 0
  fi
  [ -n "$email" ] || email="${user}@localhost"
  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ gitea admin user create --username $user --admin"
    return 0
  fi
  tries=0
  while [ "$tries" -lt 20 ]; do
    if as_root -u "$GITEA_USER" env USER="$GITEA_USER" HOME="$GITEA_HOME" GITEA_WORK_DIR="$GITEA_HOME" \
      /usr/local/bin/gitea admin user create \
      --config /etc/gitea/app.ini \
      --username "$user" --password "$pass" --email "$email" \
      --admin --must-change-password=false >/tmp/gitea-admin.out 2>&1
    then
      echo "gitea admin user: $user"
      rm -f /tmp/gitea-admin.out
      return 0
    fi
    if grep -qiE 'already exists|been taken|previously' /tmp/gitea-admin.out 2>/dev/null; then
      echo "gitea admin user exists: $user"
      rm -f /tmp/gitea-admin.out
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  echo "note: could not create Gitea admin yet — Gitea may still be migrating."
  echo "      later: sudo -u $GITEA_USER GITEA_WORK_DIR=$GITEA_HOME /usr/local/bin/gitea admin user create --config /etc/gitea/app.ini --username $user --password '…' --email $email --admin"
  rm -f /tmp/gitea-admin.out
  return 0
}

gitea_store_admin_pass() {
  pass=$1
  dest=${STARDUST:-/srv/stardust}/state/secrets/gitea-admin.txt
  if [ "${DRYRUN:-0}" -eq 1 ] || [ -z "$pass" ]; then
    return 0
  fi
  if [ -f "$dest" ]; then
    echo "exists: $dest (unchanged)"
    return 0
  fi
  as_root mkdir -p "$(dirname "$dest")"
  tmp=$(mktemp)
  printf '%s\n' "$pass" >"$tmp"
  as_root install -m 0640 "$tmp" "$dest"
  rm -f "$tmp"
  as_root chown "${OWNER:-deploy}:stardust" "$dest" 2>/dev/null || true
  echo "wrote $dest"
}

# --- main phase ------------------------------------------------------------

gitea_run_phase() {
  echo "checking whether Gitea is installed on this host"

  if gitea_report_status; then
    echo "Gitea is installed — will not download a binary or rewrite app.ini"
    gitea_prompt_git_template
    return 0
  fi

  inst_def=Y
  if [ "${ROLE:-devel}" = test ] || [ "${ROLE:-devel}" = live ]; then
    inst_def=N
  fi
  env_inst=$(gitea_env GITEA_INSTALL)

  if [ "${DRYRUN:-0}" -eq 1 ]; then
    echo "+ Gitea missing — would prompt: install on this host? default $inst_def"
    echo "+ system user git (nologin, locked, HOME /var/lib/gitea — like deploy)"
    echo "+ prompt: public hostname, Apache proxy, SSH port 2222, database, admin, owner, SSH alias"
    echo "+ download dl.gitea.com (never the Gitea homepage); sha256; /usr/local/bin/gitea"
    echo "+ write /etc/gitea/app.ini only if absent (RUN_USER=git SSH_USER=git START_SSH_SERVER)"
    echo "+ init script + optional Apache vhost stardust-gitea"
    echo "+ STARDUST_GIT_TEMPLATE=git@HOST:OWNER/%s.git"
    gitea_prompt_git_template
    return 0
  fi

  if [ -z "$env_inst" ] && ! gitea_can_prompt; then
    echo "Gitea is not installed, and this run has no keyboard"
    echo "  (stdin is not a terminal and /dev/tty is unusable)."
    echo "Re-run from a real terminal to be prompted, or:"
    echo "  GITEA_INSTALL=Y ./install-stardust.sh -m ${ROLE:-devel}"
    echo "  (optional: GITEA_DOMAIN GITEA_OWNER GITEA_SSH_HOST …)"
    echo "Skipping the forge for now. Other steps are unchanged."
    return 0
  fi

  if [ -n "$env_inst" ]; then
    do_install=$env_inst
  elif gitea_can_prompt; then
    gitea_prompt_intro
    do_install=$(gitea_ask "Install Gitea on this host?  (Y/n)" "$inst_def" "$GITEA_HELP_INSTALL" \
      "Needed: Y or n. Y installs a Git forge on THIS machine. n if GitHub or another host already is the forge.")
  else
    do_install=$inst_def
  fi

  if ! gitea_yes "$do_install"; then
    echo "skip Gitea binary — still need a git URL template for platform-add"
    gitea_prompt_git_template
    return 0
  fi

  ver_def=1.27.3
  ver=${GITEA_VERSION:-}
  domain=${GITEA_DOMAIN:-}
  proxy=${GITEA_PROXY:-}
  ssh_mode=${GITEA_SSH:-}
  db_type=${GITEA_DB:-}
  admin=${GITEA_ADMIN:-}
  admin_email=${GITEA_ADMIN_EMAIL:-}
  admin_pass=${GITEA_ADMIN_PASS:-}
  owner=${GITEA_OWNER:-}
  ssh_host=${GITEA_SSH_HOST:-}
  http_port=${GITEA_HTTP_PORT:-3000}

  if gitea_can_prompt; then
    [ -n "$ver" ] || ver=$(gitea_ask "Gitea version to download" "$ver_def" "$GITEA_HELP_VERSION" \
      "Needed: a three-part version (1.27.3). Not a URL, not latest. Enter keeps the default.")
    [ -n "$domain" ] || domain=$(gitea_ask "Public hostname for the forge  (browser + git SSH)" "$(gitea_default_domain)" "$GITEA_HELP_DOMAIN" \
      "Needed: a hostname that resolves here (git.devel, git.starhq.knarr). Not an IP.")
    [ -n "$proxy" ] || proxy=$(gitea_ask "Put Apache in front of Gitea?  (Y/n)" "Y" "$GITEA_HELP_PROXY" \
      "Needed: Y or n. Y is http://HOSTNAME/ through Apache. n is http://HOSTNAME:3000/ straight to Gitea.")
    [ -n "$ssh_mode" ] || ssh_mode=$(gitea_ask "SSH for git clone/push: gitea (nologin Unix user) or system" "gitea" "$GITEA_HELP_SSH" \
      "Needed: gitea (recommended — Unix user git stays nologin like deploy). system needs a login shell; we will not.")
    [ -n "$db_type" ] || db_type=$(gitea_ask "Database: sqlite3 or mysql" "sqlite3" "$GITEA_HELP_DB" \
      "Needed: the word sqlite3 (one file, default) or mysql (MariaDB already on this host).")
    admin_def=${HUMAN:-admin}
    [ -n "$admin" ] || admin=$(gitea_ask "Gitea admin username" "$admin_def" "$GITEA_HELP_ADMIN" \
      "Needed: a Gitea web login (letters, digits, hyphen). This is not a Linux account.")
    [ -n "$admin_email" ] || admin_email=$(gitea_ask "Gitea admin email" "${admin}@${domain}" "$GITEA_HELP_ADMIN_EMAIL" \
      "Needed: an email on that Gitea user. Need not be a real mailbox unless you enable mail later.")
    if [ -z "$admin_pass" ]; then
      admin_pass=$(gitea_ask_secret "Gitea admin password" "$GITEA_HELP_ADMIN_PASS" \
        "Needed: the password you will type at the Gitea web login. Empty generates one and shows it once.")
    fi
    [ -n "$ssh_host" ] || ssh_host=$(gitea_ask "Git SSH host alias — HOST in git@HOST:org/repo.git" "$(gitea_default_ssh_host)" "$GITEA_HELP_SSH_HOST" \
      "Needed: the HOST in git@HOST:org/repo.git — usually an SSH alias like gitea-starhq.")
    [ -n "$owner" ] || owner=$(gitea_ask "Git owner/org — first path after the colon" "" "$GITEA_HELP_OWNER" \
      "Needed: the org or username after the colon (myorg in git@HOST:myorg/ecom.git). Empty skips the clone template.")
  else
    [ -n "$ver" ] || ver=$ver_def
    [ -n "$domain" ] || domain=$(gitea_default_domain)
    [ -n "$proxy" ] || proxy=Y
    [ -n "$ssh_mode" ] || ssh_mode=gitea
    [ -n "$db_type" ] || db_type=sqlite3
    [ -n "$admin" ] || admin=${HUMAN:-admin}
    [ -n "$admin_email" ] || admin_email="${admin}@${domain}"
    [ -n "$ssh_host" ] || ssh_host=$(gitea_default_ssh_host)
  fi

  [ -n "$ver" ] || ver=$ver_def
  [ -n "$domain" ] || domain=$(gitea_default_domain)
  [ -n "$http_port" ] || http_port=3000
  case $ver in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "note: version '$ver' is not N.N.N — using $ver_def"; ver=$ver_def ;;
  esac
  case $domain in
    *[0-9].[0-9].[0-9].[0-9]*) echo "note: hostname looks like an IP — git URLs and certs will be ugly" ;;
  esac
  case $db_type in mysql|MariaDB|mariadb) db_type=mysql ;; *) db_type=sqlite3 ;; esac
  case $ssh_mode in
    system)
      echo "note: OpenSSH-as-git needs a login shell. Unix user $GITEA_USER stays"
      echo "      nologin like deploy, so git clone uses Gitea's own SSH (port 2222)."
      echo "      git@ in URLs is SSH_USER ($GITEA_SSH_USER), not a Linux account."
      ssh_mode=gitea
      ;;
    gitea|builtin|internal|'') ssh_mode=gitea ;;
    *) ssh_mode=gitea ;;
  esac

  if gitea_yes "$proxy"; then
    http_addr=127.0.0.1
    root_url="http://${domain}/"
  else
    if [ "${LOCALHOST:-0}" -eq 1 ]; then
      http_addr=127.0.0.1
    else
      http_addr=0.0.0.0
    fi
    root_url="http://${domain}:${http_port}/"
  fi

  start_ssh=true
  if [ -n "${GITEA_SSH_PORT:-}" ]; then
    ssh_port=$GITEA_SSH_PORT
  elif gitea_can_prompt; then
    ssh_port=$(gitea_ask "Gitea SSH listen port" "2222" "$GITEA_HELP_SSH_PORT" \
      "Needed: TCP port for Gitea's own SSH. 2222 is the usual pick. CSF does not open this for you.")
  else
    ssh_port=2222
  fi
  if [ "${LOCALHOST:-0}" -eq 1 ]; then
    ssh_listen=127.0.0.1
  else
    ssh_listen=0.0.0.0
  fi

  db_pass=""
  if [ "$db_type" = mysql ]; then
    db_pass=$(gitea_rand)
  fi

  generated=0
  if [ -z "$admin_pass" ]; then
    admin_pass=$(gitea_rand)
    generated=1
  fi

  arch=$(gitea_arch)
  echo "gitea plan: ver=$ver arch=$arch domain=$domain proxy=$proxy ssh=$ssh_mode db=$db_type"

  gitea_ensure_user || {
    echo "note: Gitea user $GITEA_USER missing — skip binary" >&2
    gitea_save_template "$ssh_host" "$owner"
    return 0
  }
  gitea_ensure_dirs
  if ! gitea_download "$ver" "$arch"; then
    echo "note: Gitea download failed — keeping any git template answers"
    gitea_save_template "$ssh_host" "$owner"
    return 0
  fi
  if [ "$db_type" = mysql ]; then
    gitea_mysql "$db_pass" || db_type=sqlite3
  fi
  gitea_write_app_ini "$domain" "$http_addr" "$http_port" "$root_url" \
    "$ssh_port" "$start_ssh" "$db_type" "$db_pass" "devel"
  gitea_write_init
  if gitea_yes "$proxy"; then
    gitea_write_apache "$domain" "$http_port"
  fi

  key=$(gitea_ensure_deploy_key)
  ssh_hn=$domain
  if [ "${LOCALHOST:-0}" -eq 1 ]; then
    ssh_hn=127.0.0.1
  fi
  gitea_write_ssh_config "$ssh_host" "$ssh_hn" "$ssh_port" "$key"

  svc_start gitea
  gitea_create_admin "$admin" "$admin_email" "$admin_pass"
  if [ "$generated" -eq 1 ]; then
    gitea_store_admin_pass "$admin_pass"
    echo "Gitea admin password (shown once): $admin_pass"
  fi

  gitea_save_template "$ssh_host" "$owner"

  echo "Gitea: browse $root_url  (admin user $admin)"
  echo "Gitea: app.ini was written only because it was absent; later runs leave it alone"
  if [ -f "${key}.pub" ]; then
    echo "Add this public key in Gitea (org deploy key, or a 'deploy' user):"
    as_root cat "${key}.pub" 2>/dev/null || cat "${key}.pub" 2>/dev/null || true
  fi
  echo "Then: sudo -u ${OWNER:-deploy} git ls-remote git@${ssh_host}:${owner:-ORG}/<platform>.git"
}


gitea_run_phase
