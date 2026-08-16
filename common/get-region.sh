#!/bin/bash
# Get region from input or environment variable
function read-region () {
  local region
  read -p "Enter Azure region [default: eastus]: " region
  region=${region:-eastus}
  echo "$region"
}
