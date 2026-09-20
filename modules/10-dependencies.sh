# modules/10-dependencies.sh
# Worker: Idempotent core system package installations

echo "📦 PHASE 1: Installing Core Dependencies"
echo "----------------------------------------"

install_apache2() {
  if ! pkg_ok apache2 && ! pkg_ok httpd; then
    install_prompt "Install Apache2 (Web Server)? [Y/n]" "Y" "Apache2 is a high-performance web server."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt) pkg_install apache2 ;;
        apk) pkg_install apache2 ;;
        dnf|yum) pkg_install httpd ;;
        *) echo "Unsupported package manager." >&2; return 1 ;;
      esac
    fi
  else
    echo "Apache2 is already installed."
  fi
  # FIX: Removed tune_apache2 from here!
}

install_php() {
  if ! pkg_ok php; then
    install_prompt "Install PHP (Hypertext Preprocessor)? [Y/n]" "Y" "PHP is required for Backdrop CMS."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt) pkg_install php php-cli php-mysql php-xml php-gd php-mbstring php-curl php-zip php-fpm php-intl php-bcmath php-imagick php-apcu ;;
        apk) pkg_install php php-cli php-mysqli php-xml php-gd php-mbstring php-curl php-zip apache2-proxy php-intl php-bcmath imagemagick ;;
        dnf|yum) pkg_install php php-cli php-mysqlnd php-xml php-gd php-mbstring php-json php-intl php-bcmath ;;
        *) echo "Unsupported package manager." >&2; return 1 ;;
      esac
    fi
  else
    echo "PHP is already installed."
  fi
  # FIX: Removed tune_php from here!
}

install_mariadb() {
  if ! pkg_ok mariadb-server && ! pkg_ok mysql-server; then
    install_prompt "Install MariaDB (Database Server)? [Y/n]" "Y" "MariaDB is required for Backdrop CMS."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt) pkg_install mariadb-server ;;
        apk) pkg_install mariadb ;;
        dnf|yum) pkg_install mariadb-server ;;
        *) echo "Unsupported package manager." >&2; return 1 ;;
      esac
    fi
  else
    echo "MariaDB is already installed."
  fi
  # FIX: Removed tune_mysql from here!
}

install_git() {
  if ! pkg_ok git; then
    install_prompt "Install Git (Version Control System)? [Y/n]" "Y" "Git is required for managing platforms."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then pkg_install git; fi
  else
    echo "Git is already installed."
  fi
}

# Inside modules/10-dependencies.sh — Fixed Permission-Safe Bee Installer

install_bee() {
  if ! command -v bee >/dev/null 2>&1; then
    install_prompt "Install Bee (Backdrop CMS CLI)? [Y/n]" "Y" "Bee is a command line utility for Backdrop CMS."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      
      echo "🌐 Querying GitHub API for the absolute latest stable Bee release tag..."
      
      if have curl && have jq; then
        LATEST_TAG=$(curl -s "https://github.com" | jq -r '.tag_name // empty')
      else
        LATEST_TAG=""
      fi

      if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" = "null" ]; then
        echo "  ⚠️ Warning: API limit reached or metadata hidden. Falling back to tracking release branch standard..."
        LATEST_TAG="1.x-1.x"
      else
        echo "  ✓ Identified latest stable release target: $LATEST_TAG"
      fi

      # FIX: Dynamically provision an isolated, temporary directory with clean root ownership barriers
      BEE_TMP_DIR=$(mktemp -d /tmp/bee-install-XXXXXX)

      # Clean up any previous production configuration path fragments
      as_root rm -rf "$BEE_DST"
      as_root mkdir -p "$(dirname "$BEE_DST")"

      echo "📥 Downloading compiled stable release package..."
      if [ "$DRYRUN" -eq 1 ]; then
        echo "+ wget -O $BEE_TMP_DIR/bee.tar.gz https://github.com{LATEST_TAG}.tar.gz"
        echo "+ tar -xzf $BEE_TMP_DIR/bee.tar.gz -C $BEE_TMP_DIR"
        echo "+ ln -sf $BEE_DST/bee.php $BEE_BIN"
      else
        # 1. Download into our isolated, owned directory context to bypass sticky bits
        as_root wget -q --show-progress -O "$BEE_TMP_DIR/bee.tar.gz" \
          "https://github.com{LATEST_TAG}.tar.gz" || \
        as_root wget -q --show-progress -O "$BEE_TMP_DIR/bee.tar.gz" \
          "https://github.com{LATEST_TAG}.tar.gz"

        # 2. Extract cleanly within our custom directory workspace boundary
        as_root tar -xzf "$BEE_TMP_DIR/bee.tar.gz" -C "$BEE_TMP_DIR"
        
        # 3. Pull folder and map accurately into standard production target locations
        EXTRACTED_DIR=$(ls -d "$BEE_TMP_DIR"/bee-*)
        as_root mv "$EXTRACTED_DIR" "$BEE_DST"
        
        # 4. Erase structural temp markers thoroughly
        as_root rm -rf "$BEE_TMP_DIR"

        # 5. Bind permissions and establish global execution link anchors
        echo "⚙️ Linking binaries into execution paths..."
        as_root chmod +x "$BEE_DST/bee.php"
        as_root ln -sf "$BEE_DST/bee.php" "$BEE_BIN"
        
        echo "  ✓ Bee stable configuration successfully deployed to $BEE_BIN."
      fi
    fi
  else
    echo "Bee is already installed at $(command -v bee)."
  fi
}
   
install_gitea() {
  if ! gitea_installed; then
    install_prompt "Install Gitea (Self-hosted Git Service)? [Y/n]" "Y" "Gitea is recommended for Stardust workflows."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      echo "🌐 Downloading Gitea binary..."
      as_root mkdir -p /tmp
      as_root wget -q --show-progress -O /tmp/gitea "https://gitea.com"
      run_root install -m 755 /tmp/gitea /usr/local/bin/gitea
      [ "$DRYRUN" -eq 0 ] && as_root rm -f /tmp/gitea
      svc_start gitea
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
      [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ] && pkg_install dnsmasq
      [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; } && pkg_install certbot python3-certbot-apache
      [ "$LOCALHOST" -eq 0 ] && [ "$DO_CSF" -eq 1 ] && pkg_install iptables perl libwww-perl liblwp-protocol-https-perl libgd-perl
      ;;
    apk)
      pkg_install apache2-utils mariadb-client mariadb-backup git curl unzip rsync acl php-intl php-bcmath imagemagick jq smartmontools haveged
      [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ] && pkg_install dnsmasq
      ;;
    dnf|yum)
      pkg_install httpd-tools mariadb-backup jq pv smartmontools irqbalance
      [ "$LOCALHOST" -eq 1 ] || [ "$ROLE" = "devel" ] && pkg_install dnsmasq
      [ "$LOCALHOST" -eq 0 ] && { [ "$ROLE" = "test" ] || [ "$ROLE" = "live" ]; } && pkg_install certbot python3-certbot-apache
      ;;
  esac
}

# Core execution sequence for Phase 1
install_apache2
install_php
install_mariadb
install_git
install_bee
install_gitea
install_extras
