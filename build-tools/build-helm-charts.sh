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

function usage {
    cat >&2 <<EOF
Usage:
$(basename $0) [ --verbose ]
Options:
    --verbose:    Verbose output
    --help:       Give this help list
EOF
}

OPTS=$(getopt -o h -l help,verbose -- "$@")
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


BUILD_OUTPUT_PATH=${MY_WORKSPACE}/std/build-helm/stx
if [ -d ${BUILD_OUTPUT_PATH} ]; then
    # Wipe out the existing dir to ensure there are no stale files
    rm -rf ${BUILD_OUTPUT_PATH}
fi
mkdir -p ${BUILD_OUTPUT_PATH}
cd ${BUILD_OUTPUT_PATH}

# Extract the helm charts
declare -a FAILED
declare -a HELM_RPMS=(
    "openstack-helm"
    "openstack-helm-infra"
    "stx-openstack-helm"
)
RPMS_DIR=${MY_WORKSPACE}/std/rpmbuild/RPMS
for helm_rpm in "${HELM_RPMS[@]}"; do
    rpm_file=$(ls ${RPMS_DIR} | grep "^${helm_rpm}-[^-]*-[^-]*.tis.noarch.rpm")
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
done

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "Failed to find or extract one or more helm packages:" >&2
    for helm_rpm in ${FAILED[@]}; do
        echo "${helm_rpm}" >&2
    done
    exit 1
fi

# Create a new tarball containing all the contents we extracted
# The folder contains usr/lib/helm.
# The new tarball is a flattened list of files
tar --transform 's/.*\///g' ${TAR_FLAGS} helm-charts.tgz usr/lib/helm/*.tgz
if [ $? -ne 0 ]; then
    echo "Failed to create the tarball" >&2
    exit 1
fi

echo "Results: ${BUILD_OUTPUT_PATH}/helm-charts.tgz"

exit 0

