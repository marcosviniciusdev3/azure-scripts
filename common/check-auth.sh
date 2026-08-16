#!/bin/bash
function check-auth() {
  echo "Checking Azure authentication..."
  if ! az account show >/dev/null 2>&1; then
      echo "Error: You are not logged in to Azure CLI inside the container."
      echo "Please log in first by running:"
      echo "  podman run -it -v azure:/root/.azure --rm mcr.microsoft.com/azure-cli:azurelinux3.0 az login"
      exit 1
  fi
  echo "Azure authentication verified."
  echo ""
}
