# List of CGTS packages to be included/installed in guest image
# If these have dependencies, they will be pulled in automatically
#
build-info

# custom cloud-init configuration

# guest extensions
guest-scale-agent
guest-host-comm
guest-client

# Latest version of the i40e drivers from Intel.
kmod-i40e
kmod-i40evf

# Latest version of the ixgbe drivers from Intel.
kmod-ixgbe
kmod-ixgbevf

# Intel QuickAssist
# qat16-guest
# qat16-guest-app
qat17

# TPM2 libs to enable vTPM on Guest
tss2
tpm2-tools
kmod-tpm

# This will help us have our automation debug TC failures when pings to VMs fail. 
qemu-guest-agent

# ima plugin for rpm
rpm-plugin-systemd-inhibit

# Add debugging tools
perf
zip
unzip
traceroute

# Add cfn-push-stats for heat demos
heat-cfntools
