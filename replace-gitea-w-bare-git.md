Inspect install-stardust.sh and all related module install/configuration  scripts. 
I want to completely remove Gitea and replace it with a lightweight, native Git CLI setup.

Please perform the following refactoring:
1. Identify and remove all Gitea setup logic (downloading Gitea binaries, SQLite forge configuration, systemd/init daemon services, web ports, admin token generation, and network API calls).
2. Ensure the script verifies that standard Git (`git`) is installed via the package manager (e.g., `apt-get install -y git` or `apk add git`).
3. Replace the Gitea repo initialization with a native bare repository structure:
   - Create a central bare repo directory at a configurable path (e.g., `~/repos/<project-name>.git` using `git init --bare`).
   - Clone or link the active working project directory to that bare repo as `origin`.
   - Configure sensible Git defaults if not set (e.g., user.name, user.email, default branch `main`).
4. If a local network transport is needed, add an optional lightweight `git daemon` flag instead of a web forge, or stick purely to filesystem paths (`file://` or direct local paths).
5. Clean up any lingering background service supervisor checks or ports that Gitea used.

Show me the diff of the changes before applying them, then test running the script with --dry-run or syntax checking (bash -n).
