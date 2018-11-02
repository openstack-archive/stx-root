#!/bin/bash
#
# Copyright (c) 2018 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This utility retrieves StarlingX helm-charts
# from the build output and re-packages them
# in a single openstack-helm.tgz tarball
#

# Required env vars
if [ -z "${MY_WORKSPACE}" -o -z "${MY_REPO}" ]; then
    echo "Environment not setup for builds" >&2
    exit 1
fi

OS=centos

function usage {
    cat >&2 <<EOF
Usage:
$(basename $0) [ --os <os> ] [ --verbose ]
Options:
    --os:         Specify base OS (eg. centos)
    --verbose:    Verbose output
    --help:       Give this help list
EOF
}

OPTS=$(getopt -o h -l help,os:,verbose -- "$@")
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
        --verbose)
            VERBOSE=true
            shift
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

if [ "$VERBOSE" = true ] ; then
    CPIO_FLAGS=-vidu
    TAR_FLAGS=-zcvf
else
    CPIO_FLAGS="-idu --quiet"
    TAR_FLAGS=-zcf
fi

SUPPORTED_OS_ARGS=('centos')
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

function get_helm_files {
    find ${GIT_LIST} -maxdepth 1 -name "${OS}_helm.inc"
}

HELM_FILES=$(get_helm_files)
if [ -z "$(echo -n ${HELM_FILES})" ]; then
    echo "Could not find ${OS}_helm.inc files" >&2
    exit 1
fi

BUILD_OUTPUT_PATH=${MY_WORKSPACE}/std/build-helm/stx
if [ -d ${BUILD_OUTPUT_PATH} ]; then
    # Wipe out the existing dir to ensure there are no stale files
    rm -rf ${BUILD_OUTPUT_PATH}
fi
mkdir -p ${BUILD_OUTPUT_PATH}
cd ${BUILD_OUTPUT_PATH}

# Extract the helm charts
declare -a FAILED
RPMS_DIR=${MY_WORKSPACE}/std/rpmbuild/RPMS
GREP_GLOB="-[^-]*-[^-]*.tis.noarch.rpm"
for helm_rpm in $(sed -e 's/#.*//' ${HELM_FILES} | sort -u); do
    case $OS in
        centos)
            # Bash globbing does not handle [^-] like regex
            # so grep needed to be used
            rpm_file=$(ls ${RPMS_DIR} | grep "^${helm_rpm}${GREP_GLOB}")
            chartfile=${RPMS_DIR}/${rpm_file}
            if [ ! -f ${chartfile} ]; then
                echo "Could not find ${helm_rpm}" >&2
                FAILED+=($helm_rpm)
                continue
            fi

            rpm2cpio ${chartfile} | cpio ${CPIO_FLAGS}
            if [ ${PIPESTATUS[0]} -ne 0 -o ${PIPESTATUS[1]} -ne 0 ]; then
                echo "Failed to extract content of ${chartfile}" >&2
                FAILED+=($helm_rpm)
            fi

            ;;
    esac
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "Failed to find or extract one or more helm packages:" >&2
    for helm_rpm in ${FAILED[@]}; do
        echo "${helm_rpm}" >&2
    done
    exit 1
fi

# Create a new tarball containing all the contents we extracted
# tgz files under helm are relocated to subdir charts.
# Files under armada are left at the top level
mkdir staging
if [ -d "usr/lib/armada" ]; then
    cp usr/lib/armada/* staging/.
fi
if [ -d "usr/lib/helm" ]; then
    cp -R usr/lib/helm staging/charts
fi
tar ${TAR_FLAGS} helm-charts.tgz -C staging/ .

if [ $? -ne 0 ]; then
    echo "Failed to create the tarball" >&2
    exit 1
fi

echo "Results: ${BUILD_OUTPUT_PATH}/helm-charts.tgz"

exit 0

