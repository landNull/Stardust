# modules/30-php.sh
# App-Centric Worker: PHP Execution Environment Engine

echo "⚙️ STEP 30: Provisioning Runtime Process Engine (PHP)"
echo "---------------------------------------------------"

php_install() {
  if ! pkg_ok php; then
    install_prompt "Install PHP (Hypertext Preprocessor)? [Y/n]" "Y" "PHP extensions required for Backdrop CMS site execution profiles."
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt) pkg_install php php-cli php-mysql php-xml php-gd php-mbstring php-curl php-zip php-fpm php-intl php-bcmath php-imagick php-apcu ;;
        apk) pkg_install php php-cli php-mysqli php-xml php-gd php-mbstring php-curl php-zip apache2-proxy php-intl php-bcmath imagemagick ;;
        dnf|yum) pkg_install php php-cli php-mysqlnd php-xml php-gd php-mbstring php-json php-intl php-bcmath ;;
      esac
    fi
  else
    echo "  PHP is already running on the system."
  fi
}

php_tune_runtime() {
  echo "  ⚙️ Customizing memory limits and runtime boundaries..."
  shared="; Stardust Shared Engine
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 120
max_input_vars = 3000
date.timezone = UTC
allow_url_include = Off
expose_php = Off
opcache.enable = 1
opcache.memory_consumption = 256
opcache.max_accelerated_files = 16000
opcache.interned_strings_buffer = 16"

  opc_web="opcache.validate_timestamps = 1
opcache.revalidate_freq = 2"
  if [ "$ROLE" = "live" ] || [ "$ROLE" = "test" ]; then opc_web="opcache.validate_timestamps = 0
opcache.revalidate_freq = 0"; fi

  web="; Stardust FPM Configuration
disable_functions = passthru,popen,proc_open,proc_close,dl,pcntl_exec,pcntl_fork
allow_url_fopen = On
session.cookie_httponly = 1
session.use_strict_mode = 1
$(printf '%b' "$opc_web")"
  if [ "$ROLE" = "live" ] || [ "$ROLE" = "test" ]; then web="${web}
session.cookie_secure = 1"; fi

  cli="; Stardust CLI Override
opcache.enable_cli = 0
opcache.validate_timestamps = 1"

  written=0
  if [ -d /etc/php ]; then
    for d in /etc/php/*/apache2/conf.d /etc/php/*/cli/conf.d /etc/php/*/fpm/conf.d; do
      [ -d "$d" ] || continue
      printf '%s\n' "$shared" | write_dropin "$d/30-stardust.ini"
      case $d in
        */cli/conf.d) printf '%s\n' "$cli" | write_dropin "$d/35-stardust-cli.ini" ;;
        *) printf '%s\n' "$web" | write_dropin "$d/35-stardust-harden.ini" ;;
      esac
      written=1
    done
  fi

  if [ "$written" -eq 0 ] && [ -d /etc/php.d ]; then
    printf '%s\n' "$shared" | write_dropin /etc/php.d/30-stardust.ini
    written=1
  fi
}

php_install
php_tune_runtime
