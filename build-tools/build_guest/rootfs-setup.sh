#!/bin/bash

BUILD_MODE=''
if [ "$1" == "--rt" ]; then
   BUILD_MODE="rt"
fi
if [ "$1" == "--std" ]; then
   BUILD_MODE="std"
fi

# Setup boot directory for syslinux configuration (/boot/extlinux.conf)
ln -s $(ls /boot/vmlinuz-*.x86_64 | head -1) /boot/vmlinuz
ln -s $(ls /boot/initramfs-*.x86_64.img | head -1) /boot/initramfs.img

# Setup root and wrsroot users
usermod -p $(openssl passwd -1 root) root
useradd -p $(openssl passwd -1 wrsroot) wrsroot

# Enable SUDO access for wrsroot
echo "wrsroot ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Enable remote root login to permit automated tools to run privileged commands
sed -i 's%^#\(PermitRootLogin \)%\1%' /etc/ssh/sshd_config
sed -i 's#^\(PermitRootLogin \).*#\1yes#' /etc/ssh/sshd_config

# Enable password login to permit automated tools to run commands
sed -i 's%^#\(PasswordAuthentication \)%\1%' /etc/ssh/sshd_config
sed -i 's#^\(PasswordAuthentication \).*#\1yes#' /etc/ssh/sshd_config

# Disable PAM authentication
sed -i 's#^\(UsePAM \).*#\1no#' /etc/ssh/sshd_config

# Prevent cloud_init for reverting our changes
sed -i 's#^\(ssh_pwauth:\).*#\1 1#' /etc/cloud/cloud.cfg
sed -i 's#^\(disable_root:\).*#\1 0#' /etc/cloud/cloud.cfg

# Setup SSHD to mark packets for QoS processing in the host (this seems to
# be broken in our version of SSHd so equivalent iptables rules are being
# added to compensate.
echo "IPQoS cs7" >> /etc/ssh/sshd_config

# Disable reverse path filtering to permit traffic testing from
# foreign routes.
sed -i 's#^\(net.ipv4.conf.*.rp_filter=\).*#\10#' /etc/sysctl.conf

# Change /etc/rc.local to touch a file to indicate that the init has
# completed.  This is required by the AVS vbenchmark tool so that it knows
# that the VM is ready to run.  This was added because VM instances take a
# long time (2-3 minutes) to resize their filesystem when run on a system with
# HDD instead of SSD.
chmod +x /etc/rc.d/rc.local
echo "touch /var/run/.init-complete" >> /etc/rc.local

if [ "$BUILD_MODE" == "rt" ]; then
   # Adjust system tuning knobs during init when using rt kernel (CGTS-7047)
   echo "echo 1 > /sys/devices/virtual/workqueue/cpumask" >> /etc/rc.local
   echo "echo 1 > /sys/bus/workqueue/devices/writeback/cpumask" >> /etc/rc.local
   echo "echo -1 > /proc/sys/kernel/sched_rt_runtime_us" >> /etc/rc.local
   echo "echo 0 > /proc/sys/kernel/timer_migration" >> /etc/rc.local
   echo "echo 10 > /proc/sys/vm/stat_interval" >> /etc/rc.local
fi

# Disable audit service by default
# With this enabled, it causes system delays when running at maximum
# capacity that impacts the traffic processing enough to cause unclean
# traffic runs when doing benchmark tests.
systemctl disable auditd

if [ "$BUILD_MODE" == "rt" ]; then
   # Additional services to disable on rt guest (CGTS-7047)
   systemctl disable polkit.service
   systemctl disable tuned.service
fi

# Clean the yum cache.  We don't want to maintain it on the guest file system.
yum clean all

# update /etc/rsyslog.conf to have OmitLocalLogging off
sed -i 's#OmitLocalLogging on#OmitLocalLogging off#g' /etc/rsyslog.conf

# select correct kernel and initrd
if [ "$BUILD_MODE" == "rt" ]; then
   PATTERN=$(rpm -q --qf '%{VERSION}-%{RELEASE}' kernel-rt)
else
   PATTERN=$(rpm -q --qf '%{VERSION}-%{RELEASE}' kernel)
fi
cd /boot
rm -f vmlinuz initramfs.img
ln -s $(ls -1 vmlinuz-$PATTERN*) vmlinuz
ln -s $(ls -1 initramfs-$PATTERN*img) initramfs.img
