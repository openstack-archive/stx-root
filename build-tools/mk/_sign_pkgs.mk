
#
# this makefile is used by the build-iso process to add file signature to all rpms
# 
# it requires a private key, passed as the variable KEY

PKGS_LIST := $(wildcard *.rpm)

# we need to skip the signature of some packages that
# might be installed in file systems that do not support extended attributes
# in the case of shim- and grub2-efi-, the UEFI configuration installs them in a VFAT file system
PKGS_TO_SKIP := $(wildcard grub2-efi-[0-9]*.x86_64.rpm grub2-efi-x64-[0-9]*.x86_64.rpm shim-[0-9]*.x86_64.rpm shim-x64-[0-9]*.x86_64.rpm shim-ia32-[0-9]*.x86_64)

PKGS_TO_SIGN = $(filter-out $(PKGS_TO_SKIP),$(PKGS_LIST))

define _pkg_sign_tmpl

_sign_$1 :
	@ rpmsign --signfiles --fskpath=$(KEY) $1
	@ chown mockbuild $1
	@ chgrp users $1

sign : _sign_$1

endef

sign :
	@echo signed all packages

$(foreach file,$(PKGS_TO_SIGN),$(eval $(call _pkg_sign_tmpl,$(file))))

