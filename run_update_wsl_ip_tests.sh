#!/bin/bash
# ==============================================================================
# Test runner script for update-wsl-ip.sh unit tests
# ==============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Running unit tests for update-wsl-ip.sh...${NC}"
echo ""

# Check if BATS is installed
if ! command -v bats &> /dev/null; then
    echo -e "${RED}Error: BATS is not installed.${NC}"
    echo ""
    echo "To install BATS:"
    echo "  - On macOS: brew install bats-core"
    echo "  - On Ubuntu/Debian: sudo apt-get install bats"
    echo "  - On other systems: See https://github.com/bats-core/bats-core#installation"
    exit 1
fi

# Run the tests
if [ "$1" == "--verbose" ] || [ "$1" == "-v" ]; then
    echo "Running in verbose mode..."
    bats -v test_update_wsl_ip.bats
else
    bats test_update_wsl_ip.bats
fi

# Check exit status
if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
else
    echo ""
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi