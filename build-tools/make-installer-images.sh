#!/bin/bash -e
## this script is called by "update-pxe-network-installer" and run in "sudo"
## created by Yong Hu (yong.hu@intel.com), 05/24/2018

function clean_rootfs {
    rootfs_dir=$1
    echo "--> remove old files in original rootfs"
    conf="$(ls ${rootfs_dir}/etc/ld.so.conf.d/kernel-*.conf)"
    echo "conf basename = $(basename $conf)"
    old_version="tbd"
    if [ -f $conf ]; then
        old_version="$(echo $(basename $conf) | rev | cut -d'.' -f2- | rev | cut -d'-' -f2-)"
    fi
    echo "old version is $old_version"
    # remove old files in original initrd.img
    # do this in chroot to avoid accidentialy wrong operations on host root
chroot $rootfs_dir /bin/bash -x <<EOF
    rm -rf ./boot/ ./etc/modules-load.d/
    if [ -n $old_version ] &&  [ -f ./etc/ld.so.conf.d/kernel-${old_version}.conf ]; then
        rm -rf ./etc/ld.so.conf.d/kernel-${old_version}.conf
        rm -rf ./lib/modules/${old_version}
    fi
    if [ -d ./usr/lib64/python2.7/site-packages/pyanaconda/ ];then
            rm -rf usr/lib64/python2.7/site-packages/pyanaconda/
        fi
        if [ -d ./usr/lib64/python2.7/site-packages/rpm/ ];then
            rm -rf usr/lib64/python2.7/site-packages/rpm/
        fi
        #find old .pyo files and delete them
        all_pyo="`find ./usr/lib64/python2.7/site-packages/pyanaconda/ usr/lib64/python2.7/site-packages/rpm/ -name *.pyo`"
        if [ -n $all ]; then
            for pyo in $all_pyo;do
                rm -f $pyo
            done
        fi
        exit
EOF
    #back to previous folder
}


echo "This script makes new initrd.img, vmlinuz and squashfs.img."
echo "NOTE: it has to be executed with *root*!"

if [ $# -lt 2 ];then
    echo "$0 <work_dir> <kernel_mode>"
    echo "kernel_mode: std or rt"
    exit -1;
fi

work_dir=$1
mode=$2
output_dir=$work_dir/output
if [ ! -d $output_dir ]; then
    mkdir -p $output_dir;
fi

if [ "$mode" != "std" ] && [ "$mode" != "rt" ]; then
    echo "ERROR: wrong kernel mode, must be std or rt"
    exit -1
fi

timestamp=$(date +%F_%H%M)

echo "---------------- start to make new initrd.img and vmlinuz -------------"
ORIG_INITRD=$work_dir/orig/initrd.img
if [ ! -f $ORIG_INITRD ];then
    echo "ERROR: $ORIG_INITRD does NOT exist!"
    exit -1
fi

kernel_rpms_dir=$work_dir/kernel-rpms
if [ ! -d $kernel_rpms_dir ];then
    echo "ERROR: $kernel_rpms_dir does NOT exist!"
    exit -1
fi

initrd_root=$work_dir/initrd.work
if [ -d $initrd_root ];then
    rm -rf $initrd_root
fi
mkdir -p $initrd_root

cd $initrd_root
# uncompress initrd.img
echo "--> uncompress original initrd.img"
/usr/bin/xzcat $ORIG_INITRD | cpio -i

echo "--> clean up $initrd_root"
clean_rootfs $initrd_root

echo "--> extract files from new kernel and its modular rpms to initrd root"
for kf in $kernel_rpms_dir/$mode/*.rpm ; do rpm2cpio $kf | cpio -idu; done

# by now new kernel and its modules exist!
# find new kernel in /boot/
echo "--> get new kernel image: vmlinuz"
new_kernel="$(ls ./boot/vmlinuz-*)"
echo $new_kernel
if [ -f $new_kernel ];then
    #copy out the new kernel
    if [ $mode == "std" ];then
        if [ -f $output_dir/new-vmlinuz ]; then
                mv -f $output_dir/new-vmlinuz $output_dir/vmlinuz-bakcup-$timestamp
        fi
        cp -f $new_kernel $output_dir/new-vmlinuz
    else
        if [ -f $output_dir/new-vmlinuz-rt ]; then
                mv -f $output_dir/new-vmlinuz-rt $output_dir/vmlinuz-rt-bakcup-$timestamp
        fi
        cp -f $new_kernel $output_dir/new-vmlinuz-rt
    fi
    kernel_name=$(basename $new_kernel)
    new_ver=$(echo $kernel_name | cut -d'-' -f2-)
    echo $new_ver
else
    echo "ERROR: new kernel is NOT found!"
    exit -1
fi

echo "-->check module dependencies in new initrd.img in chroot context"
chroot $initrd_root /bin/bash -x <<EOF
/usr/sbin/depmod -aeF "/boot/System.map-$new_ver" "$new_ver"
if [ $? == 0 ]; then echo "module dependencies are satisfied!" ; fi
## Remove the bisodevname package!
rm -f ./usr/lib/udev/rules.d/71-biosdevname.rules ./usr/sbin/biosdevname
exit
EOF

echo "--> Rebuild the initrd"
if [ -f $output_dir/new-initrd.img ]; then
    mv -f $output_dir/new-initrd.img $output_dir/initrd.img-bakcup-$timestamp
fi
find . | cpio -o -H newc | xz --check=crc32 --x86 --lzma2=dict=512KiB > $output_dir/new-initrd.img
if [ $? != 0 ];then
    echo "ERROR: failed to create new initrd.img"
    exit -1
fi

cd $work_dir

if [ -f $output_dir/new-initrd.img ];then
    ls -l $output_dir/new-initrd.img
else
    echo "ERROR: new-initrd.img is not generated!"
    exit -1
fi

if [ -f $output_dir/new-vmlinuz ];then
    ls -l $output_dir/new-vmlinuz
else
    echo "ERROR: new-vmlinuz is not generated!"
    exit -1
fi

echo "---------------- start to make new squashfs.img -------------"
ORIG_SQUASHFS=$work_dir/orig/squashfs.img
if [ ! -f $ORIG_SQUASHFS ];then
    echo "ERROR: $ORIG_SQUASHFS does NOT exist!"
    exit -1
fi

rootfs_rpms_dir=$work_dir/rootfs-rpms
if [ ! -d $rootfs_rpms_dir ];then
    echo "ERROR: $rootfs_rpms_dir does NOT exist!"
    exit -1
fi

# make squashfs.mnt and ready and umounted
if [ ! -d $work_dir/squashfs.mnt ];then
    mkdir -p $work_dir/squashfs.mnt
else
    # in case it was mounted previously
    mnt_path=$(mount | grep "squashfs.mnt" | cut -d' ' -f3-3)
    if [ x"$mnt_path" != "x" ] &&  [ "$(basename $mnt_path)" == "squashfs.mnt" ];then
        umount $work_dir/squashfs.mnt
    fi
fi

# make squashfs.work ready and umounted
squashfs_root="$work_dir/squashfs.work"
# Now mount the rootfs.img file:
if [ ! -d $squashfs_root ];then
    mkdir -p $squashfs_root
else
    # in case it was mounted previously
    mnt_path=$(mount | grep "$(basename $squashfs_root)" | cut -d' ' -f3-3)
    if [ x"$mnt_path" != "x" ] &&  [ "$(basename $mnt_path)" == "$(basename $squashfs_root)" ];then
        umount $squashfs_root
    fi
fi

echo $ORIG_SQUASHFS
mount -o loop -t squashfs $ORIG_SQUASHFS $work_dir/squashfs.mnt

if [ ! -d ./LiveOS ]; then
    mkdir -p ./LiveOS ;
fi

echo "--> copy rootfs.img from original squashfs.img to LiveOS folder"
cp -f ./squashfs.mnt/LiveOS/rootfs.img ./LiveOS/.

echo "--> done to copy rootfs.img, umount squashfs.mnt"
umount ./squashfs.mnt

echo "--> mount rootfs.img into $squashfs_root"
mount -o loop LiveOS/rootfs.img $squashfs_root

echo "--> clean up ./squashfs-rootfs from original squashfs.img in chroot context"
clean_rootfs $squashfs_root

cd $squashfs_root
echo "--> extract files from rootfs-rpms to squashfs root"
for ff in $rootfs_rpms_dir/*.rpm ; do rpm2cpio $ff | cpio -idu; done

echo "--> extract files from kernel and its modular rpms to squashfs root"
for kf in $kernel_rpms_dir/$mode/*.rpm ; do rpm2cpio $kf | cpio -idu; done

echo "-->check module dependencies in new squashfs.img in chroot context"
#we are using the same new  kernel-xxx.rpm, so the $new_ver is the same
chroot $squashfs_root /bin/bash -x <<EOF
/usr/sbin/depmod -aeF "/boot/System.map-$new_ver" "$new_ver"
if [ $? == 0 ]; then echo "module dependencies are satisfied!" ; fi
## Remove the bisodevname package!
rm -f ./usr/lib/udev/rules.d/71-biosdevname.rules ./usr/sbin/biosdevname
exit
EOF

# come back to the original work dir
cd $work_dir

echo "--> unmount $squashfs_root"
umount $squashfs_root
#rename the old version
if [ -f $output_dir/new-squashfs.img ]; then
    mv -f $output_dir/new-squashfs.img $output_dir/squashfs.img-backup-$timestamp
fi

echo "--> make the new squashfs image"
mksquashfs LiveOS $output_dir/new-squashfs.img -keep-as-directory -comp xz -b 1M
if [ $? == 0 ];then
    ls -l $output_dir/new-squashfs.img
else
    echo "ERROR: failed to make a new squashfs.img"
    exit -1
fi

echo "--> done successfully!"
