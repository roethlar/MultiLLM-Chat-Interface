#!/bin/bash

# Multi-Ollama Deployment Test Cycle Script
# Quickly uninstall and redeploy for testing

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Multi-Ollama Test Cycle${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check if we're in the right directory
if [ ! -f "deploy-arch.sh" ] || [ ! -f "uninstall.sh" ]; then
    echo -e "${RED}Error: Please run this script from the directory containing deploy-arch.sh and uninstall.sh${NC}"
    exit 1
fi

# Step 1: Uninstall
echo -e "${YELLOW}Step 1: Uninstalling previous deployment...${NC}"
bash uninstall.sh
echo

# Step 2: Wait a moment
echo -e "${YELLOW}Step 2: Waiting 3 seconds for cleanup...${NC}"
sleep 3

# Step 3: Deploy
echo -e "${YELLOW}Step 3: Deploying fresh installation...${NC}"
bash deploy-arch.sh

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Test Cycle Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Access your fresh deployment at: ${YELLOW}http://localhost:3000${NC}"
echo