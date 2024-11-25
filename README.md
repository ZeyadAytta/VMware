# VMware
Ansible Automation Tasks for VMware
1- Install Ansible VMware community
  # ansible-galaxy collection install community.vmware
  Verify installation
  # ansible-galaxy collection list | grep community.vmware
  Install Required Python Libraries
  # pip install pyvmomi requests
  # pip install vSphere-Automation-SDK
2- Make sure that the Templates that you're are creating VMs from have VMwareTools installed.

Creating VMs:
  1- You can create VMs by changing parameters in the vars.yml file. Then run the below command
    # ansible-playbook create-vms.yml -e "@vars.yml" 
  
