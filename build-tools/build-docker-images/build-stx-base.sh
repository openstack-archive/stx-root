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
IMAGE_VERSION=
PUSH=no
DOCKER_USER=${USER}
DOCKER_REGISTRY=
declare -a REPO_LIST
REPO_OPTS=
LOCAL=no
CLEAN=no

function usage {
    cat >&2 <<EOF
Usage:
$(basename $0)

Options:
    --os:         Specify base OS (valid options: ${SUPPORTED_OS_ARGS[@]})
    --os-version: Specify OS version
    --version:    Specify version for output image
    --repo:       Software repository (Format: name,baseurl), can be specified multiple times
    --local:      Use local build for software repository (cannot be used with --repo)
    --push:       Push to docker repo
    --user:       Docker repo userid
    --registry:   Docker registry
    --clean:      Remove image(s) from local registry

EOF
}

OPTS=$(getopt -o h -l help,os:,os-version:,version:,repo:,push,user:,registry:,local,clean -- "$@")
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
        --version)
            IMAGE_VERSION=$2
            shift 2
            ;;
        --repo)
            REPO_LIST+=($2)
            shift 2
            ;;
        --local)
            LOCAL=yes
            shift
            ;;
        --push)
            PUSH=yes
            shift
            ;;
        --user)
            DOCKER_USER=$2
            shift 2
            ;;
        --registry)
            # Add a trailing / if needed
            DOCKER_REGISTRY="${2%/}/"
            shift 2
            ;;
        --clean)
            CLEAN=yes
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

if [ -z "${IMAGE_VERSION}" ]; then
    IMAGE_VERSION=${OS_VERSION}
fi

if [ ${#REPO_LIST[@]} -eq 0 ]; then
    # Either --repo or --local must be specified
    if [ "${LOCAL}" = "yes" ]; then
        REPO_LIST+=("local-std,http://${HOSTNAME}:8088${MY_WORKSPACE}/std/rpmbuild/RPMS")
        REPO_LIST+=("stx-distro,http://${HOSTNAME}:8088${MY_REPO}/cgcs-centos-repo/Binary")
    else
        echo "Either --local or --repo must be specified" >&2
        exit 1
    fi
else
    if [ "${LOCAL}" = "yes" ]; then
        echo "Cannot specify both --local and --repo" >&2
        exit 1
    fi
fi

BUILDDIR=${MY_WORKSPACE}/std/build-images/stx-${OS}
if [ -d ${BUILDDIR} ]; then
    # Leftover from previous build
    rm -rf ${BUILDDIR}
fi

mkdir -p ${BUILDDIR}
if [ $? -ne 0 ]; then
    echo "Failed to create ${BUILDDIR}" >&2
    exit 1
fi

# Get the Dockerfile
SRC_DOCKERFILE=${MY_SCRIPT_DIR}/stx-${OS}/Dockerfile
cp ${SRC_DOCKERFILE} ${BUILDDIR}

# Generate the stx.repo file
STX_REPO_FILE=${BUILDDIR}/stx.repo
for repo in ${REPO_LIST[@]}; do
    repo_name=$(echo $repo | awk -F, '{print $1}')
    repo_baseurl=$(echo $repo | awk -F, '{print $2}')

    if [ -z "${repo_name}" -o -z "${repo_baseurl}" ]; then
        echo "Invalid repo specified: ${repo}" >&2
        echo "Expected format: name,baseurl" >&2
        exit 1
    fi

    cat >>${STX_REPO_FILE} <<EOF
[${repo_name}]
name=${repo_name}
baseurl=${repo_baseurl}
enabled=1
gpgcheck=0
skip_if_unavailable=1
metadata_expire=0

EOF

    REPO_OPTS="${REPO_OPTS} --enablerepo=${repo_name}"
done

# Check to see if the OS image is already pulled
docker images --format '{{.Repository}}:{{.Tag}}' ${OS}:${OS_VERSION} | grep -q "^${OS}:${OS_VERSION}$"
BASE_IMAGE_PRESENT=$?

# Build the image
IMAGE_NAME=${DOCKER_REGISTRY}${DOCKER_USER}/stx-${OS}:${IMAGE_VERSION}

docker build \
    --build-arg RELEASE=${OS_VERSION} \
    --build-arg REPO_OPTS="${REPO_OPTS}" \
    --tag ${IMAGE_NAME} ${BUILDDIR}
if [ $? -ne 0 ]; then
    echo "Failed running docker build command" >&2
    exit 1
fi

if [ "${PUSH}" = "yes" ]; then
    # Push the image
    echo "Pushing image: ${IMAGE_NAME}"
    docker push ${IMAGE_NAME}
    if [ $? -ne 0 ]; then
        echo "Failed running docker push command" >&2
        exit 1
    fi
fi

if [ "${CLEAN}" = "yes" ]; then
    # Delete the images
    echo "Deleting image: ${IMAGE_NAME}"
    docker image rm ${IMAGE_NAME}
    if [ $? -ne 0 ]; then
        echo "Failed running docker image rm command" >&2
        exit 1
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

