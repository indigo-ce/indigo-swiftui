#!/bin/bash

set -e # Exit on error
set -x # Print commands for debugging and to keep stdout active

# Set environment variables for non-interactive mode
export MISE_YES=1
export MISE_INTERACTIVE=0
export TUIST_CI=1
export TUIST_STATS_OPT_OUT=true

# Install mise (tool version manager)
curl https://mise.jdx.dev/install.sh | sh

# Add mise to PATH for this session
export PATH="$HOME/.local/bin:$PATH"

# Install Tuist using the version specified in mise.toml
mise install || { echo "Failed to install Tuist via mise"; exit 1; }

# Change to repository root directory (parent of ci_scripts)
cd "$(dirname "$0")/.." || { echo "Failed to change to repository root"; exit 1; }

# Install external dependencies
# Pass --verbose to keep stdout active during long dependency fetches
mise exec -- tuist install --verbose || { echo "Failed to install dependencies"; exit 1; }

# Generate the Xcode workspace and projects using Tuist
# Keep stdout alive to prevent Xcode Cloud's 15-minute inactivity timeout
GENERATE_EXIT=0
# Give the heartbeat its own process group so its sleep child dies with it
set -m
while true; do echo "tuist generate running..."; sleep 60; done &
KEEPALIVE_PID=$!
mise exec -- tuist generate || GENERATE_EXIT=$?
kill -- -"$KEEPALIVE_PID" 2>/dev/null || true
wait "$KEEPALIVE_PID" 2>/dev/null || true
# A sleep forked while the first kill scanned the group escapes it; stop it too
kill -- -"$KEEPALIVE_PID" 2>/dev/null || true
set +m
[ "$GENERATE_EXIT" -ne 0 ] && { echo "Failed to generate Xcode workspace"; exit 1; }

# Skip macro fingerprint validation for Xcode Cloud
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
