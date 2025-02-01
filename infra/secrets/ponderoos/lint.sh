#!/bin/bash
# Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
# SPDX-License-Identifier: Proprietary


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check if identity file is provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 /path/to/identity.txt [directory]"
    echo "If directory is not specified, current directory will be used"
    exit 1
fi

IDENTITY_FILE="$1"
DIRECTORY="${2:-.}"  # Use current directory if not specified

# Check if identity file exists
if [ ! -f "$IDENTITY_FILE" ]; then
    echo "Error: Identity file not found: $IDENTITY_FILE"
    exit 1
fi

# Function to test decryption of a file
test_decrypt() {
    local file="$1"
    # Attempt to decrypt first few bytes to test file
    # Redirect both stdout and stderr to /dev/null
    if age --decrypt -i "$IDENTITY_FILE" "$file" > /dev/null 2>&1 < /dev/null; then
        echo -e "${GREEN}OK${NC}: $file"
        return 0
    else
        echo -e "${RED}FAILED${NC}: $file"
        return 1
    fi
}

# Counter for failed files
failed_count=0
total_count=0

# Process all .age files in the directory
echo "Testing age-encrypted files in $DIRECTORY..."
echo "Using identity file: $IDENTITY_FILE"
echo "----------------------------------------"

while IFS= read -r -d '' file; do
    total_count=$((total_count + 1))
    if ! test_decrypt "$file"; then
        failed_count=$((failed_count + 1))
    fi
done < <(find "$DIRECTORY" -type f -name "*.age" -print0)

# Print summary
echo "----------------------------------------"
echo "Summary:"
echo "Total files tested: $total_count"
echo "Failed decryption: $failed_count"
echo "Successful decryption: $((total_count - failed_count))"

# Exit with error if any files failed
[ "$failed_count" -gt 0 ] && exit 1 || exit 0
