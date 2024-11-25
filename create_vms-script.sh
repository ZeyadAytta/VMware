#!/bin/bash

# First, verify we're in a bash shell
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires bash to run."
    exit 1
fi

# Enable error handling
set -e

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Declare global arrays
declare -a vm_names
declare -a vm_types
declare -a vm_templates
declare -a vm_folders
declare -a vm_ips
declare -a vm_cpus
declare -a vm_memories
declare -a vm_passwords
declare -a vm_netmasks
declare -a vm_gateways
declare -a vm_primary_dns
declare -a vm_secondary_dns
declare -a vm_domains
declare -a vm_searchdomains

# Global variables
vcenter_hostname=""
vcenter_username=""
vcenter_password=""
datacenter=""
cluster=""
datastore=""
network_name=""

# Check requirements
check_requirements() {
    local missing_req=0

    if ! command -v ansible-playbook > /dev/null 2>&1; then
        echo -e "${RED}Error: ansible-playbook not found. Please install Ansible first.${NC}"
        missing_req=1
    fi

    if ! command -v ping > /dev/null 2>&1; then
        echo -e "${RED}Error: ping command not found. Please install iputils-ping package.${NC}"
        missing_req=1
    fi

    if [ ! -f "create_vms.yml" ]; then
        echo -e "${RED}Error: create_vms.yml playbook not found in current directory.${NC}"
        missing_req=1
    fi
    
    # Check if VMware community collection is installed
    if ! ansible-galaxy collection list | grep -q "community.vmware"; then
        echo -e "${RED}Error: community.vmware collection not found. Please install it using:${NC}"
        echo -e "${GREEN}ansible-galaxy collection install community.vmware${NC}"
        missing_req=1
    else
        # Get installed version
        local vmware_version=$(ansible-galaxy collection list | grep "community.vmware" | awk '{print $2}')
        echo -e "${GREEN}Found community.vmware collection version ${vmware_version}${NC}"
    fi
    
    # Check if PyVmomi is installed (required by VMware modules)
    if ! python3 -c "import pyVmomi" 2>/dev/null; then
        echo -e "${RED}Error: PyVmomi not found. Please install it using:${NC}"
        echo -e "${GREEN}pip install PyVmomi${NC}"
        missing_req=1
    
   fi
    if [ $missing_req -eq 1 ]; then
        exit 1
    fi
}

# Function to clean input string
clean_input() {
    local input="$1"
    echo "$input" | sed -r "s/\x1B\[[0-9;]*[mK]//g" | tr -d '\010\177' | tr -cd '[:print:]' | awk '{$1=$1};1'
}

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS='.'
        read -ra IP_PARTS <<< "$ip"
        for part in "${IP_PARTS[@]}"; do
            if [ $part -lt 0 ] || [ $part -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Function to get non-empty input
get_input() {
    local prompt="$1"
    local default_value="$2"
    local value=""
    local cleaned_value=""

    while true; do
        read -p "$prompt" value
        cleaned_value=$(clean_input "$value")

        if [ -n "$default_value" ] && [ -z "$cleaned_value" ]; then
            echo "$default_value"
            break
        elif [ -z "$cleaned_value" ]; then
            echo -e "${RED}This field cannot be empty. Please provide a value.${NC}" >&2
            continue
        else
            echo "$cleaned_value"
            break
        fi
    done
}

# Function to get valid IP input
get_ip_input() {
    local prompt="$1"
    local default_value="$2"
    local ip=""

    while true; do
        ip=$(get_input "$prompt" "$default_value")
        if validate_ip "$ip"; then
            echo "$ip"
            break
        else
            echo -e "${RED}Invalid IP address format. Please try again.${NC}" >&2
        fi
    done
}

# Function to collect variables
collect_variables() {
    echo -e "\n${BLUE}====== Number of VMs ======${NC}"
    
    while true; do
        vm_count=$(get_input "How many VMs would you like to create? ")
        if [[ "$vm_count" =~ ^[1-9][0-9]*$ ]]; then
            break
        else
            echo -e "${RED}Please enter a valid number greater than 0${NC}"
        fi
    done

    # Common infrastructure details
    vcenter_hostname=$(get_input "Enter vCenter FQDN or IP address: ")
    vcenter_username=$(get_input "Enter vCenter username [administrator@vsphere.local]: " "administrator@vsphere.local")
    read -s -p "Enter vCenter password: " vcenter_password
    echo
    vcenter_password=$(clean_input "$vcenter_password")

    datacenter=$(get_input "Enter datacenter name : " )
    cluster=$(get_input "Enter cluster name : ")
    datastore=$(get_input "Enter datastore name : " )
    network_name=$(get_input "Enter Portgroup or Segment name  [e.g. VM Network]: ")

    # Collect variables for each VM
    for ((i=1; i<=vm_count; i++)); do
        echo -e "\n${BLUE}====== VM #$i Configuration ======${NC}"

        # VM Configuration
        while true; do
            local vm_OStype=$(get_input "Enter OS type for VM #$i (linux/windows): ")
            if [[ "$vm_OStype" =~ ^(linux|windows)$ ]]; then
                vm_types+=("$vm_OStype")
                default_folder="${vm_OStype}_vms"
                break
            else
                echo -e "${RED}Invalid OS type. Please enter 'linux' or 'windows'${NC}"
            fi
        done

        vm_templates+=("$(get_input "Enter template name in vCenter for VM #$i: ")")
        vm_names+=("$(get_input "Enter name for VM #$i: ")")
        vm_folders+=("$(get_input "Enter VM folder path for VM #$i [$default_folder]: " "$default_folder")")

        read -s -p "Enter password for VM #$i [default: VMware1!]: " vm_pass
        echo
        vm_passwords+=("$(clean_input "${vm_pass:-VMware1!}")")

        # Network Configuration
        echo -e "\n${BLUE}Network Configuration for VM #$i${NC}"
        vm_ips+=("$(get_ip_input "Enter IP address for VM #$i: ")")

        while true; do
            subnet_mask=$(get_input "Enter subnet mask for VM #$i (e.g., 255.255.255.0): ")
            if [[ $subnet_mask =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                vm_netmasks+=("$subnet_mask")
                break
            else
                echo -e "${RED}Invalid subnet mask format${NC}"
            fi
        done

        vm_gateways+=("$(get_ip_input "Enter gateway IP for VM #$i: ")")
        vm_primary_dns+=("$(get_ip_input "Enter primary DNS for VM #$i: ")")
        vm_secondary_dns+=("$(get_ip_input "Enter secondary DNS for VM #$i: ")")
        vm_domains+=("$(get_input "Enter domain for VM #$i: ")")
        vm_searchdomains+=("$(get_input "Enter domain search for VM #$i: ")")

        # Hardware Configuration
        while true; do
            local cpu=$(get_input "Enter number of CPUs for VM #$i [1]: " "1")
            if [[ "$cpu" =~ ^[0-9]+$ ]]; then
                vm_cpus+=("$cpu")
                break
            else
                echo -e "${RED}Invalid CPU number. Please enter a positive number.${NC}"
            fi
        done

        while true; do
            local memory=$(get_input "Enter memory in MB for VM #$i [512]: " "512")
            if [[ "$memory" =~ ^[0-9]+$ ]]; then
                vm_memories+=("$memory")
                break
            else
                echo -e "${RED}Invalid memory value. Please enter a positive number.${NC}"
            fi
        done
    done
}

# Function to create vars file
create_vars_file() {
    cat > vars.yml <<EOF
---
vcenter_hostname: "$vcenter_hostname"
vcenter_username: "$vcenter_username"
vcenter_password: "$vcenter_password"
datacenter: "$datacenter"
cluster: "$cluster"
datastore: "$datastore"
network_name: "$network_name"

vms:
EOF

    for ((i=0; i<${#vm_names[@]}; i++)); do
        cat >> vars.yml <<EOF
  - name: "${vm_names[$i]}"
    os_type: "${vm_types[$i]}"
    template: "${vm_templates[$i]}"
    folder: "${vm_folders[$i]}"
    password: "${vm_passwords[$i]}"
    ip_address: "${vm_ips[$i]}"
    netmask: "${vm_netmasks[$i]}"
    gateway: "${vm_gateways[$i]}"
    primary_dns: "${vm_primary_dns[$i]}"
    secondary_dns: "${vm_secondary_dns[$i]}"
    domain: "${vm_domains[$i]}"
    domain_search: "${vm_searchdomains[$i]}"
    cpu: ${vm_cpus[$i]}
    memory: ${vm_memories[$i]}
EOF
    done

    echo -e "\n${GREEN}Variables file created successfully!${NC}"
    echo -e "${BLUE}Contents of vars.yml:${NC}"
    cat vars.yml
}

# Display collected information
display_summary() {
    echo -e "\n${BLUE}====== Common Infrastructure Summary ======${NC}"
    echo -e "vCenter Hostname: ${GREEN}$vcenter_hostname${NC}"
    echo -e "vCenter Username: ${GREEN}$vcenter_username${NC}"
    echo -e "Datacenter: ${GREEN}$datacenter${NC}"
    echo -e "Cluster: ${GREEN}$cluster${NC}"
    echo -e "Datastore: ${GREEN}$datastore${NC}"
    echo -e "Network Name: ${GREEN}$network_name${NC}"

    echo -e "\n${BLUE}====== VM Configurations ======${NC}"
    for ((i=0; i<${#vm_names[@]}; i++)); do
        echo -e "\n${YELLOW}VM #$((i+1)) Details:${NC}"
        echo -e "Name: ${GREEN}${vm_names[$i]}${NC}"
        echo -e "OS Type: ${GREEN}${vm_types[$i]}${NC}"
        echo -e "Template: ${GREEN}${vm_templates[$i]}${NC}"
        echo -e "Folder: ${GREEN}${vm_folders[$i]}${NC}"
        echo -e "IP Address: ${GREEN}${vm_ips[$i]}${NC}"
        echo -e "Subnet Mask: ${GREEN}${vm_netmasks[$i]}${NC}"
        echo -e "Gateway: ${GREEN}${vm_gateways[$i]}${NC}"
        echo -e "Primary DNS: ${GREEN}${vm_primary_dns[$i]}${NC}"
        echo -e "Secondary DNS: ${GREEN}${vm_secondary_dns[$i]}${NC}"
        echo -e "Domain: ${GREEN}${vm_domains[$i]}${NC}"
        echo -e "Domain Search: ${GREEN}${vm_searchdomains[$i]}${NC}"
        echo -e "CPU Cores: ${GREEN}${vm_cpus[$i]}${NC}"
        echo -e "Memory (MB): ${GREEN}${vm_memories[$i]}${NC}"
    done
}

# Main script execution
main() {
    clear
    check_requirements

    # Show prerequisites
    echo -e "${BLUE}====== VM Deployment Prerequisites ======${NC}\n"
    echo -e "${YELLOW}You will need to provide the following information:${NC}\n"

    echo -e "${BLUE}vCenter Details:${NC}"
    echo "- vCenter hostname"
    echo "- vCenter username"
    echo "- vCenter password"
    echo "- Datacenter name"
    echo "- Cluster name"
    echo "- VM folder path"
    echo "- Datastore name"

    echo -e "\n${BLUE}VM Configuration:${NC}"
    echo "- Number of VMs to create"
    echo "- OS type for each VM (linux/windows)"
    echo "- Template name for each VM"
    echo "- VM names"
    echo "- VM passwords"

    echo -e "\n${BLUE}Network Configuration for each VM:${NC}"
    echo "- IP address"
    echo "- Subnet mask"
    echo "- Gateway"
    echo "- DNS servers"
    echo "- Domain name"
    echo "- Domain search"

    echo -e "\n${BLUE}Hardware Configuration for each VM:${NC}"
    echo "- Number of CPUs"
    echo "- Memory in MB"

    # Ask if ready to proceed
    echo -e "\n${GREEN}Do you have all these details ready? (y/n)${NC}"
    read -r ready

    if [[ ! $ready =~ ^[Yy]$ ]]; then
        echo -e "\n${YELLOW}Please gather all required information and run the script again.${NC}"
        exit 0
    fi

    # Collect variables
    collect_variables

    # Show summary and confirm
    display_summary

    # Final confirmation and execution
    echo -e "\n${YELLOW}Is this information correct? (y/n)${NC}"
    read -r confirm

    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "\n${RED}Setup cancelled. Please run the script again.${NC}"
        exit 1
    fi

    # Create variables file
    create_vars_file

    # Execute playbook
    echo -e "\n${BLUE}====== Ready to Execute ======${NC}"
    echo -e "The playbook will be executed with:"
    echo -e "${YELLOW}ansible-playbook create_vms.yml -e \"@vars.yml\"${NC}"

    echo -e "\n${GREEN}Would you like to proceed with the deployment? (y/n)${NC}"
    read -r deploy

    if [[ $deploy =~ ^[Yy]$ ]]; then
        ansible-playbook create_vms.yml -e "@vars.yml"
        exit_code=$?

        if [ $exit_code -eq 0 ]; then
            echo -e "\n${GREEN}Deployment completed successfully!${NC}"
        else
            echo -e "\n${RED}Deployment failed with exit code $exit_code${NC}"
        fi
    else
        echo -e "\n${YELLOW}Deployment cancelled.${NC}"
    fi

    # Cleanup
    echo -e "\n${BLUE}Would you like to keep the variables file (vars.yml)? (y/n)${NC}"
    read -r keep_vars
    if [[ ! $keep_vars =~ ^[Yy]$ ]]; then
        rm vars.yml
        echo -e "${GREEN}Variables file removed.${NC}"
    fi

    echo -e "\n${BLUE}====== Process Complete ======${NC}"
}

# Execute main function
main
