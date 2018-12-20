#!/bin/bash
#
# Copyright (c) 2018 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This utility builds the StarlingX wheel tarball
#

MY_SCRIPT_DIR=$(dirname $(readlink -f $0))

# Required env vars
if [ -z "${MY_WORKSPACE}" -o -z "${MY_REPO}" ]; then
    echo "Environment not setup for builds" >&2
    exit 1
fi

SUPPORTED_OS_ARGS=('centos')
OS=centos
OS_VERSION=7.5.1804
OPENSTACK_RELEASE=pike
VERSION=$(date --utc '+%Y.%m.%d.%H.%M') # Default version, using timestamp
PUSH=no
CLEAN=no
DOCKER_USER=${USER}

# List of top-level services for images, which should not be listed in upper-constraints.txt
SKIP_CONSTRAINTS=(
    ceilometer
    cinder
    glance
    gnocchi
    heat
    horizon
    ironic
    keystone
    magnum
    murano
    neutron
    nova
)

function usage {
    cat >&2 <<EOF
Usage:
$(basename $0)

Options:
    --os:         Specify base OS (valid options: ${SUPPORTED_OS_ARGS[@]})
    --os-version:     Specify OS version
    --release:    Openstack release (default: pike)
    --push:       Push to docker repo
    --user:       Docker repo userid
    --version:    Version for pushed image (if used with --push)

EOF
}

OPTS=$(getopt -o h -l help,os:,os-version:,push,clean,user:,release:,version: -- "$@")
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
        --push)
            PUSH=yes
            shift
            ;;
        --clean)
            CLEAN=yes
            shift
            ;;
        --user)
            DOCKER_USER=$2
            shift 2
            ;;
        --release)
            OPENSTACK_RELEASE=$2
            shift 2
            ;;
        --version)
            VERSION=$2
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

# Build the base wheels and retrieve the StarlingX wheels
${MY_SCRIPT_DIR}/build-base-wheels.sh --os ${OS} --os-version ${OS_VERSION} --release ${OPENSTACK_RELEASE}
if [ $? -ne 0 ]; then
    echo "Failure running build-base-wheels.sh" >&2
    exit 1
fi

${MY_SCRIPT_DIR}/get-stx-wheels.sh --os ${OS} --release ${OPENSTACK_RELEASE}
if [ $? -ne 0 ]; then
    echo "Failure running get-stx-wheels.sh" >&2
    exit 1
fi

BUILD_OUTPUT_PATH=${MY_WORKSPACE}/std/build-wheels-${OS}-${OPENSTACK_RELEASE}/tarball
if [ -d ${BUILD_OUTPUT_PATH} ]; then
    # Wipe out the existing dir to ensure there are no stale files
    rm -rf ${BUILD_OUTPUT_PATH}
fi
mkdir -p ${BUILD_OUTPUT_PATH}
cd ${BUILD_OUTPUT_PATH}

IMAGE_NAME=stx-${OS}-${OPENSTACK_RELEASE}-wheels

TARBALL_FNAME=${MY_WORKSPACE}/std/build-wheels-${OS}-${OPENSTACK_RELEASE}/${IMAGE_NAME}.tar
if [ -f ${TARBALL_FNAME} ]; then
    rm -f ${TARBALL_FNAME}
fi

# Download the global-requirements.txt and upper-constraints.txt files
if [ "${OPENSTACK_RELEASE}" = "master" ]; then
    OPENSTACK_BRANCH=${OPENSTACK_RELEASE}
else
    OPENSTACK_BRANCH=stable/${OPENSTACK_RELEASE}
fi

wget https://raw.githubusercontent.com/openstack/requirements/${OPENSTACK_BRANCH}/global-requirements.txt
if [ $? -ne 0 ]; then
    echo "Failed to download global-requirements.txt" >&2
    exit 1
fi

wget https://raw.githubusercontent.com/openstack/requirements/${OPENSTACK_BRANCH}/upper-constraints.txt
if [ $? -ne 0 ]; then
    echo "Failed to download upper-constraints.txt" >&2
    exit 1
fi

# Delete $SKIP_CONSTRAINTS from upper-constraints.txt, if any present
for name in ${SKIP_CONSTRAINTS[@]}; do
    grep -q "^${name}===" upper-constraints.txt
    if [ $? -eq 0 ]; then
        # Delete the module
        sed -i "/^${name}===/d" upper-constraints.txt
    fi
done

# Copy the base and stx wheels, updating upper-constraints.txt as necessary
for wheel in ../base/*.whl ../stx/wheels/*.whl; do
    # Get the wheel name and version from the METADATA
    METADATA=$(unzip -p ${wheel} '*/METADATA')
    name=$(echo "${METADATA}" | grep '^Name:' | awk '{print $2}')
    version=$(echo "${METADATA}" | grep '^Version:' | awk '{print $2}')

    if [ -z "${name}" -o -z "${version}" ]; then
        echo "Failed to parse name or version from $(readlink -f ${wheel})" >&2
        exit 1
    fi

    echo "Adding ${name}-${version}..."

    cp ${wheel} .
    if [ $? -ne 0 ]; then
        echo "Failed to copy $(readlink -f ${wheel})" >&2
        exit 1
    fi

    # Update the upper-constraints file, if necessary
    skip_constraint=1
    for skip in ${SKIP_CONSTRAINTS[@]}; do
        if [ "${name}" = "${skip}" ]; then
            skip_constraint=0
            continue
        fi
    done

    if [ ${skip_constraint} -eq 0 ]; then
        continue
    fi

    grep -q "^${name}===${version}\(;.*\)*$" upper-constraints.txt
    if [ $? -eq 0 ]; then
        # This version already exists in the upper-constraints.txt
        continue
    fi

    grep -q "^${name}===" upper-constraints.txt
    if [ $? -eq 0 ]; then
        # Update the version
        sed -i "s/^${name}===.*/${name}===${version}/" upper-constraints.txt
    else
        # Add the module
        echo "${name}===${version}" >> upper-constraints.txt
    fi
done

echo "Creating $(basename ${TARBALL_FNAME})..."
tar cf ${TARBALL_FNAME} *
if [ $? -ne 0 ]; then
    echo "Failed to create the tarball" >&2
    exit 1
fi

echo "Done."

if [ "${PUSH}" = "yes" ]; then
    #
    # Push generated wheels tarball to docker registry
    #
    docker import ${TARBALL_FNAME} ${DOCKER_USER}/${IMAGE_NAME}:${VERSION}
    if [ $? -ne 0 ]; then
        echo "Failed command:" >&2
        echo "docker import ${TARBALL_FNAME} ${DOCKER_USER}/${IMAGE_NAME}:${VERSION}" >&2
        exit 1
    fi

    docker tag ${DOCKER_USER}/${IMAGE_NAME}:${VERSION} ${DOCKER_USER}/${IMAGE_NAME}:latest
    if [ $? -ne 0 ]; then
        echo "Failed command:" >&2
        echo "docker tag ${DOCKER_USER}/${IMAGE_NAME}:${VERSION} ${DOCKER_USER}/${IMAGE_NAME}:latest" >&2
        exit 1
    fi

    docker push ${DOCKER_USER}/${IMAGE_NAME}:${VERSION}
    if [ $? -ne 0 ]; then
        echo "Failed command:" >&2
        echo "docker push ${DOCKER_USER}/${IMAGE_NAME}:${VERSION}" >&2
        exit 1
    fi

    docker push ${DOCKER_USER}/${IMAGE_NAME}:latest
    if [ $? -ne 0 ]; then
        echo "Failed command:" >&2
        echo "docker import ${TARBALL_FNAME} ${DOCKER_USER}/${IMAGE_NAME}:${VERSION}" >&2
        exit 1
    fi

    if [ "${CLEAN}" = "yes" ]; then
        echo "Deleting docker images ${DOCKER_USER}/${IMAGE_NAME}:${VERSION} ${DOCKER_USER}/${IMAGE_NAME}:latest"
        docker image rm ${DOCKER_USER}/${IMAGE_NAME}:${VERSION} ${DOCKER_USER}/${IMAGE_NAME}:latest
        if [ $? -ne 0 ]; then
            echo "Failed command:" >&2
            echo "docker image rm ${DOCKER_USER}/${IMAGE_NAME}:${VERSION} ${DOCKER_USER}/${IMAGE_NAME}:latest" >&2
            exit 1
        fi
    fi
fi

exit 0

