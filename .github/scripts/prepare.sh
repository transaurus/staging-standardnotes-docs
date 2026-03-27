#!/usr/bin/env bash
set -euo pipefail

# prepare.sh for standardnotes/docs
# Docusaurus 2.0.0-alpha.73, Yarn v1 (classic), Node 20
# Fixes:
#   1. sass + sass-loader@10 (node-sass incompatible with Node 20; sass-loader>=11 needs webpack 5)
#   2. Patch nested postcss packages to export ./package.json (ERR_PACKAGE_PATH_NOT_EXPORTED)

REPO_URL="https://github.com/standardnotes/docs"
BRANCH="main"
REPO_DIR="source-repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Clone (skip if already exists) ---
if [ ! -d "$REPO_DIR" ]; then
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

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
# Replace docusaurus-plugin-sass 0.1.x (uses node-sass) with 0.2.x (uses sass/dart-sass)
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

# --- Apply fixes.json if present ---
FIXES_JSON="$SCRIPT_DIR/fixes.json"
if [ -f "$FIXES_JSON" ]; then
    echo "[INFO] Applying content fixes..."
    node -e "
    const fs = require('fs');
    const path = require('path');
    const fixes = JSON.parse(fs.readFileSync('$FIXES_JSON', 'utf8'));
    for (const [file, ops] of Object.entries(fixes.fixes || {})) {
        if (!fs.existsSync(file)) { console.log('  skip (not found):', file); continue; }
        let content = fs.readFileSync(file, 'utf8');
        for (const op of ops) {
            if (op.type === 'replace' && content.includes(op.find)) {
                content = content.split(op.find).join(op.replace || '');
                console.log('  fixed:', file, '-', op.comment || '');
            }
        }
        fs.writeFileSync(file, content);
    }
    for (const [file, cfg] of Object.entries(fixes.newFiles || {})) {
        const c = typeof cfg === 'string' ? cfg : cfg.content;
        fs.mkdirSync(path.dirname(file), {recursive: true});
        fs.writeFileSync(file, c);
        console.log('  created:', file);
    }
    "
fi

echo "[DONE] Repository is ready for docusaurus commands."
