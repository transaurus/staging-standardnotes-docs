#!/usr/bin/env bash
set -euo pipefail

# rebuild.sh for standardnotes/docs
# Runs on existing source tree (no clone). Installs deps, applies fixes, builds.
# Docusaurus 2.0.0-alpha.73, Yarn v1 (classic), Node 20

# --- Node version ---
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -f "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    nvm install 20
    nvm use 20
fi
echo "[INFO] Node: $(node --version)"
echo "[INFO] NPM: $(npm --version)"

# --- Ensure yarn (classic v1) is available ---
if ! command -v yarn &> /dev/null; then
    echo "[INFO] Installing yarn..."
    npm install -g yarn
fi
echo "[INFO] Yarn: $(yarn --version)"

# --- Fix: node-sass doesn't build on Node 20+ ---
echo "[INFO] Patching package.json for sass/sass-loader compatibility..."
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
if (pkg.dependencies && pkg.dependencies['docusaurus-plugin-sass']) {
    pkg.dependencies['docusaurus-plugin-sass'] = '^0.2.0';
}
pkg.dependencies['sass'] = '^1.49.0';
if (!pkg.resolutions) pkg.resolutions = {};
pkg.resolutions['sass-loader'] = '10.x';
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
console.log('[INFO] package.json patched');
"

# --- Install dependencies ---
echo "[INFO] Installing dependencies..."
yarn install --no-frozen-lockfile

# --- Fix: postcss ERR_PACKAGE_PATH_NOT_EXPORTED on Node 12+ ---
echo "[INFO] Patching postcss packages to export ./package.json..."
node -e "
const fs = require('fs');
const { execSync } = require('child_process');
const files = execSync('find node_modules -name package.json -path \"*/postcss/package.json\"').toString().trim().split('\n').filter(Boolean);
let patched = 0;
for (const f of files) {
    try {
        const pkg = JSON.parse(fs.readFileSync(f, 'utf8'));
        if (pkg.exports && !pkg.exports['./package.json']) {
            pkg.exports['./package.json'] = './package.json';
            fs.writeFileSync(f, JSON.stringify(pkg, null, 2));
            patched++;
        }
    } catch (e) {}
}
console.log('[INFO] Patched ' + patched + ' postcss instances');
"

# --- Build ---
echo "[INFO] Building..."
# Node 17+ changed OpenSSL behavior; webpack 4 (Docusaurus alpha.73) requires legacy provider
NODE_OPTIONS=--openssl-legacy-provider yarn build

echo "[DONE] Build complete."
