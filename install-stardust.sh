# Inside stardust-install.sh:
echo "Executing Stardust Setup Framework..."

for module in "$HERE/modules/"[0-9][0-9]-*.sh; do
  if [ -f "$module" ]; then
    . "$module"
  fi
done
