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
kmod-i40e-rt
kmod-i40evf-rt

# Latest version of the ixgbe drivers from Intel.
kmod-ixgbe-rt
kmod-ixgbevf-rt

# Configure connectx pro devices to ethernet mode.
# This is needed for PT devices
# mlx4-config

# Intel QuickAssist
# qat16-guest
# qat16-guest-app
qat17-rt

# TPM2 libs to enable vTPM on Guest
tss2
tpm2-tools
kmod-tpm-rt

# ima plugin for RPM
rpm-plugin-systemd-inhibit

# Add cfn-push-stats for heat demos
heat-cfntools
