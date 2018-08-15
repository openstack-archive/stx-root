# List of packages to be included/installed in RT guest image
# If these have dependencies, they will be pulled in automatically
#

# This will help us have our automation debug TC failures when pings to VMs fail. 
qemu-guest-agent

# Add debugging tools
zip
unzip
traceroute

# Add cfn-push-stats for heat demos
heat-cfntools
