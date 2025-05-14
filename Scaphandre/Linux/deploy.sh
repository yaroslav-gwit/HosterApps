#!/usr/bin/env bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root"
    exit 1
fi

# Check if wget is installed
if ! [ -x "$(command -v wget)" ]; then
    echo "Error: wget is not installed. Please install wget and try again."
    exit 2
fi

# Download scaphandre binary
if [ -x "$(command -v scaphandre)" ]; then
    echo "error: scaphandre is already installed. please use the update or uninstall script instead."
    exit 3
fi
