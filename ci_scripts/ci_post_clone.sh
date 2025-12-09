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
mise exec -- tuist generate || { echo "Failed to generate Xcode workspace"; exit 1; }

# Skip macro fingerprint validation for Xcode Cloud
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
