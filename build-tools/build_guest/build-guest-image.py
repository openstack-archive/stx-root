#!/usr/bin/env python

#
# Build a bootable guest image from the supplied rootfs archive
#

import getopt
import guestfs
import os
import sys


MBR_FILE='/usr/share/syslinux/mbr.bin'
MBR_SIZE=440

def build_image(inputfile, outputfile, extrasize, trace):
    g = guestfs.GuestFS(python_return_dict=True)

    # Set the trace flag so that we can see each libguestfs call.
    if trace:
        g.set_trace(1)

    # Create a raw-format sparse disk image with padding of size
    inputsize = os.path.getsize(inputfile)
    g.disk_create(outputfile, "raw", inputsize + extrasize)

    # Attach the new disk image to libguestfs.
    g.add_drive_opts(outputfile, format="raw", readonly=0)

    # Run the libguestfs back-end.
    g.launch()

    # Get the list of devices.  Because we only added one drive
    # above, we expect that this list should contain a single
    # element.
    devices = g.list_devices()
    assert(len(devices) == 1)

    # Partition the disk as one single MBR partition.
    g.part_disk(devices[0], "mbr")

    # Get the list of partitions.  We expect a single element, which
    # is the partition we have just created.
    partitions = g.list_partitions()
    assert(len(partitions) == 1)

    # Create a filesystem on the partition.
    # NOTE: extlinux does not support 64-bit file systems
    g.mkfs("ext4", partitions[0], features="^64bit")

    # Now mount the filesystem so that we can add files.
    g.mount(partitions[0], "/")

    # Upload file system files and directories.
    g.tar_in(inputfile, "/")

    # Install the boot loader
    g.extlinux("/boot")

    # Unmount the file systems.
    g.umount_all();

    # Write the master boot record.
    with open(MBR_FILE, mode='rb') as mbr:
        mbr_data = mbr.read()
        assert(len(mbr_data) == MBR_SIZE)
        g.pwrite_device(devices[0], mbr_data, 0)

    # Mark the device as bootable.
    g.part_set_bootable(devices[0], 1, 1)
    
    # Label the boot disk for root identification
    g.set_label(partitions[0], "wrs_guest")

    # Shutdown and close guest image
    g.shutdown()
    g.close()


def exit_usage(result=0):
    print('USAGE: -i <input-file> -o <output-file> [-s <extra-bytes>]')
    sys.exit(result)


def main(argv):
    inputfile = None
    outputfile = None
    extrasize = None
    trace = False

    try:
        opts, args = getopt.getopt(argv,"hxi:o:s:",
                                   ["input=", "output=", "size="])
    except getopt.GetoptError:
        exit_usage(2)
    for opt, arg in opts:
        if opt == '-h':
            exit_usage()
        if opt == '-x':
            trace = True
        elif opt in ("-i", "--input"):
            inputfile = arg
        elif opt in ("-o", "--output"):
            outputfile = arg
        elif opt in ("-s", "--size"):
            extrasize = int(arg)

    if not inputfile:
        print(stderr, "ERROR: missing input file")
        exit_usage(-1)

    if not outputfile:
        print(stderr, "ERROR: missing output file")
        exit_usage(-1)

    if not extrasize:
        extrasize = 0

    build_image(inputfile, outputfile, extrasize, trace)


if __name__ == "__main__":
    main(sys.argv[1:])
