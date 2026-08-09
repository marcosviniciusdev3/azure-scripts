#!/bin/bash
set -e

# Containerized Azure CLI wrapper
# Automatically adjusts -it based on whether we are in a terminal/piped context
source ./azure-cli.sh

echo "============================================="
echo "        Azure Instance Probing Utility       "
echo "============================================="

# 1. Check Login
echo "Checking Azure authentication..."
if ! az account show >/dev/null 2>&1; then
    echo "Error: You are not logged in to Azure CLI inside the container."
    echo "Please log in first by running:"
    echo "  podman run -it -v azure:/root/.azure --rm mcr.microsoft.com/azure-cli:azurelinux3.0 az login"
    exit 1
fi
echo "Azure authentication verified."
echo ""

# 2. Region Selection
read -p "Enter Azure region [default: eastus]: " region
region=${region:-eastus}
echo "Using region: $region"
echo ""

# 3. Dynamic VM Size Querying
echo "Fetching available VM sizes in '$region' (this may take a few seconds)..."
# List all VM sizes formatted as a table
az vm list-sizes --location "$region" --output table
echo ""

# 4. Generate unique names for resource group and VM
rand_id=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6 ; echo '')
rg_name="rg-probe-${rand_id}"
vm_name="vm-probe-${rand_id}"

# 5. Create temporary resource group
echo "Creating temporary resource group '$rg_name'..."
az group create --name "$rg_name" --location "$region" --output table

# Register cleanup handler to execute on script exit/interruption
cleanup() {
    echo ""
    echo "============================================="
    echo "Cleaning up: Deleting resource group '$rg_name'..."
    az group delete --name "$rg_name" --yes
    echo "Cleanup complete. Resource group deleted."
}
trap cleanup EXIT

# 6. Interactive Creation & Retry Loop
while true; do
    echo "--------------------------------------------- "
    read -p "Enter VM size to create (e.g. Standard_B1s): " vm_size
    if [ -z "$vm_size" ]; then
        echo "Error: VM size cannot be empty."
        continue
    fi

    echo "Attempting to create VM '$vm_name' (Size: $vm_size, Image: Ubuntu 24.04 LTS)..."
    if az vm create \
        --resource-group "$rg_name" \
        --name "$vm_name" \
        --image "Ubuntu2404" \
        --size "$vm_size" \
        --admin-username azureuser \
        --generate-ssh-keys \
        --output table; then
        
        echo "VM created successfully in Azure!"
        break
    else
        echo "VM creation failed for size '$vm_size'."
        read -p "Would you like to try another VM size? [Y/n]: " try_again
        try_again=${try_again:-y}
        if [[ ! "$try_again" =~ ^[Yy]$ ]]; then
            echo "Exiting."
            exit 1
        fi
    fi
done

# 7. Probing Network Connectivity
echo ""
echo "============================================="
echo "              Probing VM Status              "
echo "============================================="

echo "Retrieving VM details..."
vm_details=$(az vm show -d -g "$rg_name" -n "$vm_name" --query "{State:powerState, IP:publicIps}" -o json)
vm_state=$(echo "$vm_details" | grep -oP '"State":\s*"\K[^"]+')
ip_address=$(echo "$vm_details" | grep -oP '"IP":\s*"\K[^"]+')

echo "Provisioning State: Succeeded"
echo "VM Power State: $vm_state"
echo "VM Public IP: $ip_address"

if [ -z "$ip_address" ]; then
    echo "Could not retrieve VM Public IP. Skipping network probe."
else
    echo "Probing Port 22 (SSH) connectivity on $ip_address..."
    # Attempt network connection with a timeout of 15 seconds
    if timeout 15 bash -c "</dev/tcp/$ip_address/22" 2>/dev/null; then
        echo "SUCCESS: Port 22 (SSH) is reachable!"
    else
        echo "FAILED: Port 22 (SSH) is not reachable."
        echo "Note: The VM might still be booting or security group rules may be blocking ICMP/TCP."
    fi
fi

echo ""
read -p "Press Enter to delete all resources (Resource Group '$rg_name') and exit..."
