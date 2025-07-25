#!/bin/bash

# Multi-Ollama Web Interface Uninstall Script
# Comprehensive cleanup for deployment testing

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="$HOME/multi-ollama-server"
SERVICE_NAME="multi-ollama"
CURRENT_USER=$(whoami)

# Function to print colored output
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Header
echo -e "${RED}============================================${NC}"
echo -e "${RED}   Multi-Ollama Uninstall Script${NC}"
echo -e "${RED}============================================${NC}"
echo

# Stop and disable systemd service
print_status "Stopping and disabling systemd service..."
if sudo systemctl is-active --quiet ${SERVICE_NAME}.service 2>/dev/null; then
    sudo systemctl stop ${SERVICE_NAME}.service
    print_success "Service stopped"
else
    print_warning "Service was not running"
fi

if sudo systemctl is-enabled --quiet ${SERVICE_NAME}.service 2>/dev/null; then
    sudo systemctl disable ${SERVICE_NAME}.service
    print_success "Service disabled"
else
    print_warning "Service was not enabled"
fi

# Remove systemd service file
print_status "Removing systemd service file..."
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    sudo systemctl daemon-reload
    print_success "Service file removed and systemd reloaded"
else
    print_warning "Service file did not exist"
fi

# Kill any running node processes for this app
print_status "Killing any running node processes..."
pkill -f "node.*server.js" 2>/dev/null && print_success "Node processes killed" || print_warning "No node processes found"

# Remove installation directory
print_status "Removing installation directory..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    print_success "Installation directory removed: $INSTALL_DIR"
else
    print_warning "Installation directory did not exist: $INSTALL_DIR"
fi

# Clean up any leftover processes on port 3000
print_status "Cleaning up processes on port 3000..."
PROCESS_ON_PORT=$(lsof -ti:3000 2>/dev/null || echo "")
if [ ! -z "$PROCESS_ON_PORT" ]; then
    kill -9 $PROCESS_ON_PORT 2>/dev/null
    print_success "Killed process on port 3000"
else
    print_warning "No process found on port 3000"
fi

# Optional: Clean up npm cache (uncomment if needed)
# print_status "Cleaning npm cache..."
# npm cache clean --force 2>/dev/null && print_success "npm cache cleaned" || print_warning "npm cache clean failed"

# Check for any remaining traces
print_status "Checking for remaining traces..."
REMAINING_FILES=$(find /home/$CURRENT_USER -name "*multi-ollama*" -type f 2>/dev/null | wc -l)
REMAINING_DIRS=$(find /home/$CURRENT_USER -name "*multi-ollama*" -type d 2>/dev/null | wc -l)

if [ $REMAINING_FILES -gt 0 ] || [ $REMAINING_DIRS -gt 0 ]; then
    print_warning "Found $REMAINING_FILES files and $REMAINING_DIRS directories with 'multi-ollama' in the name"
    print_warning "You may want to review these manually:"
    find /home/$CURRENT_USER -name "*multi-ollama*" 2>/dev/null | head -10
else
    print_success "No remaining traces found"
fi

# Final status
echo
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Uninstall Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo
echo -e "${BLUE}What was removed:${NC}"
echo -e "  ✓ Systemd service: ${YELLOW}${SERVICE_NAME}${NC}"
echo -e "  ✓ Installation directory: ${YELLOW}${INSTALL_DIR}${NC}"
echo -e "  ✓ Node.js processes for the app"
echo -e "  ✓ Processes using port 3000"
echo
echo -e "${BLUE}What was preserved:${NC}"
echo -e "  • Node.js and npm (system packages)"
echo -e "  • SQLite (system package)"
echo -e "  • Ollama (system package)"
echo
echo -e "${GREEN}Ready for fresh deployment!${NC}"
echo -e "Run ${YELLOW}bash test.sh${NC} to deploy again."
echo