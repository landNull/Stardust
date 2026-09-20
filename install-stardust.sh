# Inside stardust-install.sh:
for module in "$HERE/modules/"[0-9][0-9]-*.sh; do
  if [ -f "$module" ]; then
    . "$module"
  fi
done
