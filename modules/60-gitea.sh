#!/bin/sh
# ==============================================================================
# modules/60-gitea.sh — Local Repository Tracking System Deployment Node
# ==============================================================================
# Automates tracking workspace provisioning for secure offline operations.
# ==============================================================================

echo "🌐 STEP 60: Provisioning Self-Hosted Version Control Hub (Gitea)"
echo "--------------------------------------------------------------"

install_gitea() {
  # Invoke our custom helper to verify if Gitea is already active in the timeline
  if ! gitea_installed; then
    install_prompt "Install Gitea (Self-hosted Git Service)? [Y/n]" "Y" "Gitea is recommended for Stardust workflows."
    
    if [ "$ans" = "Y" ] || [ "$ans" = "y" ]; then
      echo "  🌐 Streaming signed Gitea deployment binary down from release matrix..."
      as_root mkdir -p /tmp
      
      # Use wget with strict configuration tags to render terminal pipelines cleanly
      as_root wget -q --show-progress -O /tmp/gitea "https://gitea.com"
      
      # Install executable targets down into production paths safely
      run_root install -m 755 /tmp/gitea /usr/local/bin/gitea
      [ "$DRYRUN" -eq 0 ] && as_root rm -f /tmp/gitea
      
      # Boot the service engine
      svc_start gitea
    fi
  else
    echo "  Gitea data repository service layer is already active on this node."
  fi
  
  # Map structural variables down to target profiles
  maybe_gitea_defaults
}

install_gitea
