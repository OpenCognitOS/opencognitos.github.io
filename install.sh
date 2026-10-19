#!/bin/bash
# OpenCognit Installer
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/OpenCognit/opencognit/main/install.sh)

set -e

CYAN="\033[38;5;80m"
CYAN2="\033[38;5;73m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BOLD="\033[1m"
RESET="\033[0m"

banner() {
  echo -e "${CYAN}${BOLD}"
  echo -e " ██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗ ██████╗  ██████╗ ███╗   ██╗██╗████████╗"
  echo -e "██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██╔═══██╗██╔════╝ ████╗  ██║██║╚══██╔══╝"
  echo -e "██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║     ██║   ██║██║  ███╗██╔██╗ ██║██║   ██║   "
  echo -e "██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║     ██║   ██║██║   ██║██║╚██╗██║██║   ██║   "
  echo -e "╚██████╔╝██║     ███████╗██║ ╚████║╚██████╗╚██████╔╝╚██████╔╝██║ ╚████║██║   ██║   "
  echo -e " ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═╝   ╚═╝  "
  echo -e ""
  echo -e "   Zero Human Company OS"
  echo -e "${RESET}"
}

ok()   { echo -e "  ${GREEN}✓${RESET} $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET} $1"; }
fail() { echo -e "  ${RED}✗${RESET} $1"; exit 1; }
info() { echo -e "  \033[2m$1${RESET}"; }
step() { echo -e "\n${CYAN}${BOLD}[$1/$2]${RESET} ${BOLD}$3${RESET}"; }

# Find a free TCP port starting from $1
find_free_port() {
  local port=$1
  while nc -z localhost "$port" 2>/dev/null; do
    port=$((port + 1))
  done
  echo "$port"
}

banner

# ── Prerequisites ─────────────────────────────────────────────────────────────
step 1 5 "Checking prerequisites…"

if ! command -v node &>/dev/null; then
  fail "Node.js not found. Install it from https://nodejs.org (v20+ required)"
fi

NODE_MAJOR=$(node -e "console.log(process.versions.node.split('.')[0])")
if [ "$NODE_MAJOR" -lt 20 ]; then
  fail "Node.js 20+ required. You have $(node -v). Get it at https://nodejs.org"
fi
ok "Node.js $(node -v)"

if ! command -v git &>/dev/null; then
  fail "Git not found. Install it from https://git-scm.com"
fi
ok "Git $(git --version | awk '{print $3}')"

# ── Project name ──────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}Project name${RESET} \033[2m(my-opencognit)\033[0m"
read -r -p "  › " PROJECT_NAME </dev/tty
PROJECT_NAME="${PROJECT_NAME:-my-opencognit}"

if [ -d "$PROJECT_NAME" ]; then
  fail "Directory '$PROJECT_NAME' already exists. Choose a different name."
fi

# ── API Key (optional) ────────────────────────────────────────────────────────
echo ""
echo -e "  \033[2mOptional: add an LLM API key now (you can also do this later in Settings)\033[0m"
echo -e "  ${BOLD}Anthropic / OpenRouter API key${RESET} \033[2m(Enter to skip)\033[0m"
read -r -p "  › " API_KEY </dev/tty

# ── Clone ─────────────────────────────────────────────────────────────────────
step 2 5 "Cloning OpenCognit…"
REPO="https://github.com/OpenCognit/opencognit.git"
git clone --depth=1 "$REPO" "$PROJECT_NAME" || fail "Could not clone $REPO — check your internet connection."
ok "Repository cloned"

cd "$PROJECT_NAME"

# ── Install dependencies ──────────────────────────────────────────────────────
step 3 5 "Installing dependencies…"
npm install --prefer-offline --silent || fail "npm install failed. Try running it manually."
ok "Dependencies installed"

# ── Secrets + Ports + DB ──────────────────────────────────────────────────────
step 4 5 "Generating secrets and initializing database…"

mkdir -p data

JWT_SECRET=$(node -e "const c=require('crypto');console.log(c.randomBytes(32).toString('hex'))")
ENCRYPTION_KEY=$(node -e "const c=require('crypto');console.log(c.randomBytes(32).toString('hex'))")

# Auto-detect free ports
BACKEND_PORT=$(find_free_port 3201)
FRONTEND_PORT=$(find_free_port 3200)
# Ensure they don't collide
if [ "$FRONTEND_PORT" = "$BACKEND_PORT" ]; then
  BACKEND_PORT=$((FRONTEND_PORT + 1))
fi

cat > .env <<EOF
PORT=${BACKEND_PORT}
VITE_BACKEND_PORT=${BACKEND_PORT}
VITE_FRONTEND_PORT=${FRONTEND_PORT}
JWT_SECRET=${JWT_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
NODE_ENV=production
# Add your LLM API keys here (or configure them later in Settings):
# ANTHROPIC_API_KEY=sk-ant-...
# OPENROUTER_API_KEY=sk-or-...
# OPENAI_API_KEY=sk-...
# OLLAMA_BASE_URL=http://localhost:11434

# For remote/phone access:
# APP_URL=https://your-domain.com
EOF

# Inject API key if provided
if [ -n "$API_KEY" ]; then
  if [[ "$API_KEY" == sk-ant-* ]]; then
    sed -i "s|# ANTHROPIC_API_KEY=sk-ant-\.\.\.|ANTHROPIC_API_KEY=${API_KEY}|" .env
  elif [[ "$API_KEY" == sk-or-* ]]; then
    sed -i "s|# OPENROUTER_API_KEY=sk-or-\.\.\.|OPENROUTER_API_KEY=${API_KEY}|" .env
  fi
  ok "API key saved"
fi

ok ".env generated (backend: ${BACKEND_PORT}, frontend: ${FRONTEND_PORT})"

npm run db:migrate --silent 2>/dev/null && ok "Database initialized" || warn "DB migration will run on first start."

# ── Build ─────────────────────────────────────────────────────────────────────
step 5 5 "Building frontend…"
npm run build --silent 2>/dev/null && ok "Frontend built" || warn "Build failed — use 'npm run dev' for development mode."

# ── Global command ────────────────────────────────────────────────────────────
INSTALL_DIR="$(pwd)"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/opencognit" <<SCRIPT
#!/bin/bash
cd "$INSTALL_DIR" && npm run dev
SCRIPT
chmod +x "$BIN_DIR/opencognit"

# Add ~/.local/bin to PATH if not already there
SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then SHELL_RC="$HOME/.bashrc"; fi

if [ -n "$SHELL_RC" ] && ! grep -q '\.local/bin' "$SHELL_RC" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
  ok "PATH updated in $SHELL_RC"
fi
export PATH="$HOME/.local/bin:$PATH"
ok "Global command 'opencognit' installed"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✓ OpenCognit is ready.${RESET}"
echo ""
echo -e "  ${BOLD}Start anywhere with:${RESET}"
echo ""
echo -e "    ${CYAN}opencognit${RESET}"
echo ""
echo -e "  Then open ${CYAN}http://localhost:${FRONTEND_PORT}${RESET} and create your admin account."
echo ""
echo -e "  \033[2mDocs: https://opencognit.mytherrablockchain.org/docs${RESET}"
echo -e "  \033[2mGitHub: https://github.com/OpenCognit/opencognit${RESET}"
echo ""
