#!/bin/sh
# ==============================================================================
# modules/30-php.sh — Runtime Process Engine & Security Policy Hardening
# ==============================================================================
# Features isolated case evaluations for dev vs production server configurations.
# ==============================================================================

echo "⚙️ STEP 30: Provisioning Runtime Process Engine (PHP)"
echo "---------------------------------------------------"

php_install() {
  # Audit the system database index to confirm if PHP core packages are present
  if ! pkg_ok php; then
    install_prompt "Install PHP (Hypertext Preprocessor)? [Y/n]" "Y" "PHP extensions required for Backdrop CMS site execution profiles."
    
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      case $PKG in
        apt)     pkg_install php php-cli php-mysql php-xml php-gd php-mbstring php-curl php-zip php-fpm php-intl php-bcmath php-imagick php-apcu ;;
        apk)     pkg_install php php-cli php-mysqli php-xml php-gd php-mbstring php-curl php-zip apache2-proxy php-intl php-bcmath imagemagick ;;
        dnf|yum) pkg_install php php-cli php-mysqlnd php-xml php-gd php-mbstring php-json php-intl php-bcmath ;;
      case_error) return 1 ;;
      esac
    fi
  else
    echo "  PHP is already running natively on this system matrix configuration."
  fi
}

php_tune_runtime() {
  echo "  ⚙️ Customizing memory limits and engine execution profiles..."
  
  # Standardize core memory footprint maps common to all runtime targets
  shared="; Stardust Shared Engine Parameters
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

  # --- ENVIRONMENT CONDITIONAL PATTERN ---
  # If the server is production/testing, lock file validation clocks down completely for performance.
  # If running a development space, allow active monitoring timestamps to remain active.
  if [ "$ROLE" = "live" ] || [ "$ROLE" = "test" ]; then
    opc_web="opcache.validate_timestamps = 0\nopcache.revalidate_freq = 0"
  else
    opc_web="opcache.validate_timestamps = 1\nopcache.revalidate_freq = 2"
  fi

  # Strip away process tracking functions inside the web parsing environment to secure assets
  web="; Stardust FPM Configuration Block
disable_functions = passthru,popen,proc_open,proc_close,dl,pcntl_exec,pcntl_fork
allow_url_fopen = On
session.cookie_httponly = 1
session.use_strict_mode = 1
$(printf '%b' "$opc_web")"

  # Secure authentication cookies if processing a production deployment stream
  if [ "$ROLE" = "live" ] || [ "$ROLE" = "test" ]; then 
    web="${web}\nsession.cookie_secure = 1"
  fi

  # Do NOT clear execution bindings on CLI profile engines—Bee needs them to execute subcommands!
  cli="; Stardust CLI Override Matrix
opcache.enable_cli = 0
opcache.validate_timestamps = 1"

  written=0
  # Verify standard directory routes are mapped before writing configuration layers
  if [ -d /etc/php ]; then
    # POSIX loop expanding across filesystem shell paths dynamically
    for d in /etc/php/*/apache2/conf.d /etc/php/*/cli/conf.d /etc/php/*/fpm/conf.d; do
      [ -d "$d" ] || continue
      
      # Inject the shared configurations down to the target environment block
      printf '%s\n' "$shared" | write_dropin "$d/30-stardust.ini"
      
      # Use an exact string match case filter to map specialized cli vs fpm boundaries
      case $d in
        */cli/conf.d) printf '%s\n' "$cli" | write_dropin "$d/35-stardust-cli.ini" ;;
        *)            printf '%s\n' "$web" | write_dropin "$d/35-stardust-harden.ini" ;;
      esac
      written=1
    done
  fi

  # Fallback handler logic targeting RedHat/CentOS configuration trees
  if [ "$written" -eq 0 ] && [ -d /etc/php.d ]; then
    printf '%s\n' "$shared" | write_dropin /etc/php.d/30-stardust.ini
    written=1
  fi
}

# Run the execution sequence
php_install
php_tune_runtime
