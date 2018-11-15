#!/bin/bash
#
# Copyright (c) 2018 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This utility sets up a docker image to build wheels
# for a set of upstream python modules.
#

# Required env vars
if [ -z "${MY_WORKSPACE}" -o -z "${MY_REPO}" ]; then
    echo "Environment not setup for builds" >&2
    exit 1
fi

DOCKER_PATH=${MY_REPO}/build-tools/build-wheels/docker
KEEP_IMAGE=no
KEEP_CONTAINER=no
OS=centos
OS_VERSION=7.5.1804
OPENSTACK_RELEASE=pike

function usage {
    cat >&2 <<EOF
Usage:
$(basename $0) [ --os <os> ] [ --keep-image ] [ --keep-container ] [ --release <release> ]

Options:
    --os:             Specify base OS (eg. centos)
    --os-version:     Specify OS version
    --keep-image:     Skip deletion of the wheel build image in docker
    --keep-container: Skip deletion of container used for the build
    --release:        Openstack release (default: pike)

EOF
}

OPTS=$(getopt -o h -l help,os:,keep-image,keep-container,release: -- "$@")
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
        --os-version)
            OS_VERSION=$2
            shift 2
            ;;
        --keep-image)
            KEEP_IMAGE=yes
            shift
            ;;
        --keep-container)
            KEEP_CONTAINER=yes
            shift
            ;;
        --release)
            OPENSTACK_RELEASE=$2
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

BUILD_OUTPUT_PATH=${MY_WORKSPACE}/std/build-wheels-${OS}-${OPENSTACK_RELEASE}/base
BUILD_IMAGE_NAME="${USER}-$(basename ${MY_WORKSPACE})-wheelbuilder:${OS}-${OPENSTACK_RELEASE}"

DOCKER_FILE=${DOCKER_PATH}/${OS}-dockerfile
WHEELS_CFG=${DOCKER_PATH}/${OPENSTACK_RELEASE}-wheels.cfg

function supported_os_list {
    for f in ${DOCKER_PATH}/*-dockerfile; do
        echo $(basename ${f%-dockerfile})
    done | xargs echo
}

if [ ! -f ${DOCKER_FILE} ]; then
    echo "Unsupported OS specified: ${OS}" >&2
    echo "Supported OS options: $(supported_os_list)" >&2
    exit 1
fi

#
# Check build output directory for unexpected files,
# ie. wheels from old builds that are no longer in wheels.cfg
#
if [ -d ${BUILD_OUTPUT_PATH} ]; then

    for f in ${BUILD_OUTPUT_PATH}/*; do
        grep -q "^$(basename $f)|" ${WHEELS_CFG}
        if [ $? -ne 0 ]; then
            echo "Deleting stale file: $f"
            rm -f $f
        fi
    done
else
    mkdir -p ${BUILD_OUTPUT_PATH}
    if [ $? -ne 0 ]; then
        echo "Failed to create directory: ${BUILD_OUTPUT_PATH}" >&2
        exit 1
    fi
fi

# Check to see if we need to build anything
BUILD_NEEDED=no
for wheel in $(cat ${WHEELS_CFG} | sed 's/#.*//' | awk -F '|' '{print $1}'); do
    if [ ! -f ${BUILD_OUTPUT_PATH}/${wheel} ]; then
        BUILD_NEEDED=yes
        break
    fi
done

if [ "${BUILD_NEEDED}" = "no" ]; then
    echo "All base wheels are already present. Skipping build."
    exit 0
fi

# Check to see if the OS image is already pulled
docker images --format '{{.Repository}}:{{.Tag}}' ${OS}:${OS_VERSION} | grep -q "^${OS}:${OS_VERSION}$"
BASE_IMAGE_PRESENT=$?

# Create the builder image
docker build \
    --build-arg RELEASE=${OS_VERSION} \
    --build-arg OPENSTACK_RELEASE=${OPENSTACK_RELEASE} \
    -t ${BUILD_IMAGE_NAME} -f ${DOCKER_PATH}/${OS}-dockerfile ${DOCKER_PATH}
if [ $? -ne 0 ]; then
    echo "Failed to create build image in docker" >&2
    exit 1
fi

# Run the image, executing the build-wheel.sh script
RM_OPT=
if [ "${KEEP_CONTAINER}" = "no" ]; then
    RM_OPT="--rm"
fi
docker run ${RM_OPT} -v ${BUILD_OUTPUT_PATH}:/wheels -i -t ${BUILD_IMAGE_NAME} /docker-build-wheel.sh

if [ "${KEEP_IMAGE}" = "no" ]; then
    # Delete the builder image
    echo "Removing docker image ${BUILD_IMAGE_NAME}"
    docker image rm ${BUILD_IMAGE_NAME}
    if [ $? -ne 0 ]; then
        echo "Failed to delete build image from docker" >&2
    fi

    if [ ${BASE_IMAGE_PRESENT} -ne 0 ]; then
        # The base image was not already present, so delete it
        echo "Removing docker image ${OS}:${OS_VERSION}"
        docker image rm ${OS}:${OS_VERSION}
        if [ $? -ne 0 ]; then
            echo "Failed to delete base image from docker" >&2
        fi
    fi
fi

# Check for failures
if [ -f ${BUILD_OUTPUT_PATH}/failed.lst ]; then
    # Failures would already have been reported
    exit 1
fi

