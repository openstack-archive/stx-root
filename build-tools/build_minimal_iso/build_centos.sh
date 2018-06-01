#!/bin/bash

# Build a basic CentOS system

CREATEREPO=$(which createrepo_c)
if [ $? -ne 0 ]; then
   CREATEREPO="createrepo"
fi

function final_touches {
   # create the repo
   cd ${ROOTDIR}/${DEST}/isolinux
   $CREATEREPO -g ../comps.xml .
   
   # build the ISO
   printf "Building image $OUTPUT_FILE\n"
   cd ${ROOTDIR}/${DEST}
   chmod 664 isolinux/isolinux.bin
   mkisofs -o $OUTPUT_FILE \
      -R -D -A 'oe_iso_boot' -V 'oe_iso_boot' \
      -b isolinux.bin -c boot.cat -no-emul-boot \
      -boot-load-size 4 -boot-info-table \
      -eltorito-alt-boot \
      -e images/efiboot.img \
            -no-emul-boot \
      isolinux/   

   isohybrid --uefi $OUTPUT_FILE
   implantisomd5 $OUTPUT_FILE

   cd $ROOTDIR
}

function setup_disk {
	tar xJf emptyInstaller.tar.xz
	mkdir ${DEST}/isolinux/Packages
}

function install_packages {
	cd ${DEST}/isolinux/Packages
	ROOT=${ROOTDIR} ../../../cgts_deps.sh --deps=../../../${MINIMAL}
	cd ${ROOTDIR}
}


ROOTDIR=$PWD
INSTALLER_SRC=basicDisk
DEST=newDisk
PKGS_DIR=all_rpms
MINIMAL=minimal_rpm_list.txt
OUTPUT_FILE=${ROOTDIR}/centosIso.iso

# Make a basic install disk (no packages, at this point)
rm -rf ${DEST}
setup_disk

# install the packages (initially from minimal list, then resolve deps)
install_packages

# build the .iso
final_touches

