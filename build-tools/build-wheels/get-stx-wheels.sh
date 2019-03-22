#!/bin/bash
#
# Copyright (c) 2018 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This utility retrieves StarlingX python wheels
# from the build output
#

# Required env vars
if [ -z "${MY_WORKSPACE}" -o -z "${MY_REPO}" ]; then
    echo "Environment not setup for builds" >&2
    exit 1
fi

SUPPORTED_OS_ARGS=('centos')
OS=centos
BUILD_STREAM=stable

function usage {
    cat >&2 <<EOF
Usage:
$(basename $0) [ --os <os> ] [ --stream <stable|dev> ]

Options:
    --os:         Specify base OS (eg. centos)
    --stream:     Openstack release (default: stable)

EOF
}

OPTS=$(getopt -o h -l help,os:,release:,stream: -- "$@")
if [ $? -ne 0 ]; then
    usage
    exit 1
fi

eval set -- "${OPTS}"

while true; do
    case $1 in
        --)
            # End of getopt arguments
            shift
            break
            ;;
        --os)
            OS=$2
            shift 2
            ;;
        --stream)
            BUILD_STREAM=$2
            shift 2
            ;;
        --release) # Temporarily keep --release support as an alias for --stream
            BUILD_STREAM=$2
            shift 2
            ;;
        -h | --help )
            usage
            exit 1
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

# Validate the OS option
VALID_OS=1
for supported_os in ${SUPPORTED_OS_ARGS[@]}; do
    if [ "$OS" = "${supported_os}" ]; then
        VALID_OS=0
        break
    fi
done
if [ ${VALID_OS} -ne 0 ]; then
    echo "Unsupported OS specified: ${OS}" >&2
    echo "Supported OS options: ${SUPPORTED_OS_ARGS[@]}" >&2
    exit 1
fi

source ${MY_REPO}/build-tools/git-utils.sh

function get_wheels_files {
    find ${GIT_LIST} -maxdepth 1 -name "${OS}_${BUILD_STREAM}_wheels.inc"
}

declare -a WHEELS_FILES=($(get_wheels_files))
if [ ${#WHEELS_FILES[@]} -eq 0 ]; then
    echo "Could not find ${OS} wheels.inc files" >&2
    exit 1
fi

BUILD_OUTPUT_PATH=${MY_WORKSPACE}/std/build-wheels-${OS}-${BUILD_STREAM}/stx
if [ -d ${BUILD_OUTPUT_PATH} ]; then
    # Wipe out the existing dir to ensure there are no stale files
    rm -rf ${BUILD_OUTPUT_PATH}
fi
mkdir -p ${BUILD_OUTPUT_PATH}
cd ${BUILD_OUTPUT_PATH}

# Extract the wheels
declare -a FAILED
for wheel in $(sed -e 's/#.*//' ${WHEELS_FILES[@]} | sort -u); do
    case $OS in
        centos)
            # Bash globbing does not handle [^\-] well,
            # so use grep instead
            wheelfile=$(ls ${MY_WORKSPACE}/std/rpmbuild/RPMS/${wheel}-* | grep -- '[^\-]*-[^\-]*.rpm')

            if [ ! -f "${wheelfile}" ]; then
                echo "Could not find ${wheel}" >&2
                FAILED+=($wheel)
                continue
            fi

            echo Extracting ${wheelfile}

            rpm2cpio ${wheelfile} | cpio -vidu
            if [ ${PIPESTATUS[0]} -ne 0 -o ${PIPESTATUS[1]} -ne 0 ]; then
                echo "Failed to extract content of ${wheelfile}" >&2
                FAILED+=($wheel)
            fi

            ;;
    esac
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "Failed to find or extract one or more wheel packages:" >&2
    for wheel in ${FAILED[@]}; do
        echo "${wheel}" >&2
    done
    exit 1
fi

exit 0

