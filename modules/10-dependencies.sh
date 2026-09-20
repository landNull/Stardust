# modules/10-dependencies.sh
# Worker: Idempotent core system package installations

echo "📦 PHASE 1: Installing Core Dependencies"
echo "----------------------------------------"

install_apache2() {
  if ! pkg_ok apache2 && ! pkg_ok httpd; then
    install_prompt "Install Apache2 (Web Server)? [Y/n]" "Y" "Apache2 is a high-performance web server. It will be configured for speed and security."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt) pkg_install apache2 ;;
        apk) pkg_install apache2 ;;
        dnf|yum) pkg_install httpd ;;
        *) echo "Unsupported package manager. Install Apache2 manually." >&2; return 1 ;;
      esac
    fi
  else
    echo "Apache2 is already installed."
  fi
  tune_apache2
}

install_php() {
  if ! pkg_ok php; then
    install_prompt "Install PHP (Hypertext Preprocessor)? [Y/n]" "Y" "PHP is a server-side scripting language for dynamic web content. It is required for Backdrop CMS."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt)
          pkg_install php php-cli php-mysql php-xml php-gd php-mbstring php-curl php-zip php-fpm php-intl php-bcmath php-imagick php-apcu
          ;;
        apk)
          pkg_install php php-cli php-mysqli php-xml php-gd php-mbstring php-curl php-zip apache2-proxy php-intl php-bcmath imagemagick
          ;;
        dnf|yum)
          pkg_install php php-cli php-mysqlnd php-xml php-gd php-mbstring php-json php-intl php-bcmath
          ;;
        *)
          echo "Unsupported package manager. Install PHP manually." >&2
          return 1
          ;;
      esac
    fi
  else
    echo "PHP is already installed."
  fi
  tune_php
}

install_mariadb() {
  if ! pkg_ok mariadb-server && ! pkg_ok mysql-server; then
    install_prompt "Install MariaDB (Database Server)? [Y/n]" "Y" "MariaDB is a relational database server, a fork of MySQL. It is required for Backdrop CMS."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt) pkg_install mariadb-server ;;
        apk) pkg_install mariadb ;;
        dnf|yum) pkg_install mariadb-server ;;
        *) echo "Unsupported package manager. Install MariaDB manually." >&2; return 1 ;;
      esac
    fi
  else
    echo "MariaDB is already installed."
  fi
  tune_mysql
}

install_git() {
  if ! pkg_ok git; then
    install_prompt "Install Git (Version Control System)? [Y/n]" "Y" "Git is a distributed version control system. It is required for managing Backdrop CMS platforms."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      pkg_install git
    fi
  else
    echo "Git is already installed."
  fi
}

install_bee() {
  if ! command -v bee >/dev/null 2>&1; then
    install_prompt "Install Bee (Backdrop CMS CLI)? [Y/n]" "Y" "Bee is a command-line tool for managing Backdrop CMS sites. It is required for Stardust operations."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      if [ ! -d "$BEE_DST" ]; then
        run_root git clone "$BEE_SRC" "$BEE_DST"
      fi
      if [ -d "$BEE_DST" ]; then
        if have composer; then
          cd "$BEE_DST"
          run_root composer install --no-dev
          run_root ln -sf "$BEE_DST/bee" "$BEE_BIN"
          echo "Bee installed to $BEE_BIN."
        else
          echo "Composer is not installed. Bee dependencies cannot be installed automatically."
          echo "Install Composer manually from https://getcomposer.org and run:"
          echo "  cd $BEE_DST && composer install --no-dev"
          echo "  ln -s $BEE_DST/bee $BEE_BIN"
        fi
      else
        error "Failed to clone Bee repository."
      fi
    fi
  else
    echo "Bee is already installed at $(command -v bee)."
  fi
}

install_gitea() {
  if ! gitea_installed; then
    install_prompt "Install Gitea (Self-hosted Git Service)? [Y/n]" "Y" \
      "Gitea is a lightweight, self-hosted Git service for managing repositories. It is optional but recommended for Stardust workflows."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      echo "🌐 Downloading the absolute latest stable Gitea binary from mirror..."
      if [ "$DRYRUN" -eq 1 ]; then
        echo "+ wget -O /tmp/gitea https://gitea.com"
      else
        as_root mkdir -p /tmp
        as_root wget -q --show-progress -O /tmp/gitea "https://gitea.com"
      fi

      echo "📦 Aligning system execution locations..."
      run_root install -m 755 /tmp/gitea /usr/local/bin/gitea
      if [ "$DRYRUN" -eq 0 ]; then
        as_root rm -f /tmp/gitea
      fi

      svc_start gitea
      echo "Gitea binary installed successfully. Verify via: gitea --version"
    fi
  else
    echo "Gitea is already installed."
  fi
  maybe_gitea_defaults
}

install_extras() {
  echo "Installing extras (logwatch, goaccess, etc.)..."
  case $PKG in
    apt)
      pkg_install apache2-utils mariadb-backup msmtp-mta unattended-upgrades needrestart logwatch goaccess etckeeper smartmontools irqbalance haveged moreutils jq pv age
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ]; then
        pkg_install dnsmasq
      fi
      if [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; }; then
        pkg_install certbot python3-certbot-apache
      fi
      if [ "$LOCALHOST" -eq 0 ] && [ "$DO_CSF" -eq 1 ]; then
        pkg_install iptables perl libwww-perl liblwp-protocol-https-perl libgd-perl
      fi
      ;;
    apk)
      pkg_install apache2-utils mariadb-client mariadb-backup git curl unzip rsync acl php-intl php-bcmath imagemagick jq smartmontools haveged
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ]; then
        pkg_install dnsmasq
      fi
      ;;
    dnf|yum)
      pkg_install httpd-tools mariadb-backup jq pv smartmontools irqbalance
      if [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ]; then
        pkg_install dnsmasq
      fi
      if [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; }; then
        pkg_install certbot python3-certbot-apache
      fi
      ;;
  esac
}

# Fire installation cascade execution loops
install_apache2
install_php
install_mariadb
install_git
install_bee
install_gitea
install_extras
