# Ansible Automation Tasks for VMware
> Hello There, This is a simple script that create linux and Windows VMs on vCenter.

## Install Ansible VMware community
   ```
   ansible-galaxy collection install community.vmware
   ```
## Verify installation
   ```
   ansible-galaxy collection list | grep community.vmware
   ```
## Install Required Python Libraries
   ```
   pip install pyvmomi requests
   pip install vSphere-Automation-SDK
   Make sure that the Templates that you're are creating VMs from have VMwareTools installed.
```
## Creating VMs:
 ### You can create VMs by changing parameters in the vars.yml file. Then run the below command
```
   vim vars.yml # add your parameters in it  
   ansible-playbook create-vms.yml -e "@vars.yml"
```
 ###  Run the create-vms-script.sh then it will ask you all required vars to deploy your VMs.
```
./create-vms-script.sh    # follow the scrip and it will execute everything
```

  
