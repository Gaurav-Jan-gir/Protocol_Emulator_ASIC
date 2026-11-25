#!/usr/bin/env bash
#=============================================================================
# Helper Script to Create and Push ProtoPlex-8 to GitHub
#=============================================================================

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_DIR}"

echo "========================================================================"
echo "ProtoPlex-8 ASIC: GitHub Publishing Helper"
echo "Repository Directory: ${REPO_DIR}"
echo "========================================================================"

# Check if gh CLI is authenticated
if gh auth status > /dev/null 2>&1; then
    echo "GitHub CLI is authenticated!"
    echo "Creating remote repository 'Protocol_Emulator_ASIC' on GitHub..."
    gh repo create Protocol_Emulator_ASIC --public --source=. --remote=origin --push || {
        echo "Repository might already exist, attempting direct push..."
        git push -u origin main
    }
    echo "Successfully pushed to GitHub: https://github.com/$(gh api user -q .login)/Protocol_Emulator_ASIC"
else
    echo "GitHub CLI is not logged in yet."
    echo ""
    echo "Please choose one of the following options:"
    echo "  1) Run 'gh auth login' to authenticate with GitHub in your browser,"
    echo "     then re-run this script."
    echo ""
    echo "  2) Create the empty repository at: https://github.com/new"
    echo "     Name: Protocol_Emulator_ASIC"
    echo "     Then run: git push -u origin main"
    echo ""
    echo "  3) If you have a Personal Access Token (PAT), run:"
    echo "     git push https://<TOKEN>@github.com/Gaurav-Jan-gir/Protocol_Emulator_ASIC.git main"
    echo "========================================================================"
fi
