#!/bin/bash
set -e

# Containerized Azure CLI wrapper
# Automatically adjusts -it based on whether we are in a terminal/piped context
source ./common/azure-cli.sh
source ./common/check-auth.sh
source ./common/get-region.sh

echo "============================================="
echo "        Azure AKS Probing Utility            "
echo "============================================="

# 1. Check Login
check-auth

# 2. Region Selection
region=$(read-region)
echo "Using region: $region"

# 3. Dynamic Node Size Querying
echo "Fetching available VM sizes in '$region' (this may take a few seconds)..."
# List all VM sizes formatted as a table
az vm list-sizes --location "$region" --output table
echo ""

# 4. Generate unique names for resource group and AKS cluster
rand_id=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6 ; echo '')
rg_name="rg-aks-probe-${rand_id}"
aks_name="aks-probe-${rand_id}"

# 5. Create temporary resource group
echo "Creating temporary resource group '$rg_name'..."
az group create --name "$rg_name" --location "$region" --output table

# Register cleanup handler to execute on script exit/interruption
cleanup() {
    echo ""
    echo "============================================="
    echo "Cleaning up: Deleting resource group '$rg_name'..."
    az group delete --name "$rg_name" --yes --no-wait || true
    echo "Cleanup complete. Resource group deletion initiated."
}
trap cleanup EXIT

# 6. Interactive Creation & Retry Loop
while true; do
    echo "--------------------------------------------- "
    read -p "Enter node VM size to create (e.g. Standard_B2s): " vm_size
    if [ -z "$vm_size" ]; then
        echo "Error: VM size cannot be empty."
        continue
    fi

    echo "Attempting to create AKS Cluster '$aks_name' (Node Size: $vm_size)..."
    if az aks create \
        --resource-group "$rg_name" \
        --name "$aks_name" \
        --node-count 1 \
        --node-vm-size "$vm_size" \
        --generate-ssh-keys \
        --output table; then

        echo "AKS Cluster created successfully in Azure!"
        break
    else
        echo "AKS creation failed for node size '$vm_size'."
        read -p "Would you like to try another VM size? [Y/n]: " try_again
        try_again=${try_again:-y}
        if [[ ! "$try_again" =~ ^[Yy]$ ]]; then
            echo "Exiting."
            exit 1
        fi
    fi
done

# 7. Probing AKS Status
echo ""
echo "============================================="
echo "              Probing AKS Status             "
echo "============================================="

echo "Retrieving AKS details..."
aks_state=$(az aks show -g "$rg_name" -n "$aks_name" --query "provisioningState" -o tsv)
aks_fqdn=$(az aks show -g "$rg_name" -n "$aks_name" --query "fqdn" -o tsv)
aks_version=$(az aks show -g "$rg_name" -n "$aks_name" --query "kubernetesVersion" -o tsv)

echo "Provisioning State: $aks_state"
echo "Kubernetes Version: $aks_version"
echo "API Server FQDN: $aks_fqdn"

if [ -z "$aks_fqdn" ]; then
    echo "Could not retrieve AKS FQDN. Skipping network probe."
else
    echo "Probing Port 443 (HTTPS) connectivity on $aks_fqdn..."
    # Attempt network connection with a timeout of 15 seconds
    if timeout 15 bash -c "</dev/tcp/$aks_fqdn/443" 2>/dev/null; then
        echo "SUCCESS: Port 443 (HTTPS) is reachable on the API Server!"
    else
        echo "FAILED: Port 443 (HTTPS) is not reachable."
    fi
fi

echo ""
read -p "Press Enter to delete all resources (Resource Group '$rg_name') and exit..."
