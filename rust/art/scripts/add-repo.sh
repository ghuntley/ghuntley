#!/bin/bash
# Add-repo script for Art Git Repository Browser
# Usage: ./add-repo.sh <repository-url> [name]
#
# This script clones a Git repository into the Art repository directory
# and optionally sets a custom name for it.

set -e

# Default repositories directory
REPO_DIR="./repositories"

# Parse command line arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <repository-url> [name]"
    exit 1
fi

REPO_URL="$1"
REPO_NAME=""

if [ $# -ge 2 ]; then
    REPO_NAME="$2"
else
    # Extract repository name from URL
    REPO_NAME=$(basename "$REPO_URL" .git)
fi

# Check if repository directory exists
if [ ! -d "$REPO_DIR" ]; then
    echo "Creating repository directory: $REPO_DIR"
    mkdir -p "$REPO_DIR"
fi

# Check if repository already exists
if [ -d "$REPO_DIR/$REPO_NAME" ]; then
    echo "Repository $REPO_NAME already exists. Use a different name or remove the existing repository."
    exit 1
fi

# Clone the repository
echo "Cloning $REPO_URL into $REPO_DIR/$REPO_NAME..."
git clone --mirror "$REPO_URL" "$REPO_DIR/$REPO_NAME"

# Create description file
echo "Enter repository description (optional):"
read DESCRIPTION
if [ -n "$DESCRIPTION" ]; then
    echo "$DESCRIPTION" > "$REPO_DIR/$REPO_NAME/description"
fi

echo "Repository $REPO_NAME added successfully."
echo "You can now browse it at http://localhost:3000/$REPO_NAME"
