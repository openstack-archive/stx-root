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
IMAGE_VERSION=
PUSH=no
PROXY=""
DOCKER_USER=${USER}
DOCKER_REGISTRY=
declare -a REPO_LIST
REPO_OPTS=
LOCAL=no
CLEAN=no
TAG_LATEST=no
LATEST_TAG=latest
HOST=${HOSTNAME}

function usage {
    cat >&2 <<EOF
Usage:
$(basename $0)

Options:
    --os:         Specify base OS (valid options: ${SUPPORTED_OS_ARGS[@]})
    --os-version: Specify OS version
    --version:    Specify version for output image
    --release:    Openstack release (default: pike)
    --repo:       Software repository (Format: name,baseurl), can be specified multiple times
    --local:      Use local build for software repository (cannot be used with --repo)
    --push:       Push to docker repo
    --proxy:      Set proxy <URL>:<PORT>
    --latest:     Add a 'latest' tag when pushing
    --latest-tag: Use the provided tag when pushing latest.
    --user:       Docker repo userid
    --registry:   Docker registry
    --clean:      Remove image(s) from local registry
    --hostname:   build repo host

EOF
}

OPTS=$(getopt -o h -l help,os:,os-version:,version:,release:,repo:,push,proxy:,latest,latest-tag:,user:,registry:,local,clean,hostname: -- "$@")
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
        --release)
            OPENSTACK_RELEASE=$2
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
        --proxy)
            PROXY=$2
            shift 2
            ;;
        --latest)
            TAG_LATEST=yes
            shift
            ;;
        --latest-tag)
            LATEST_TAG=$2
            shift 2
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
        --hostname)
            HOST=$2
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

if [ -z "${IMAGE_VERSION}" ]; then
    IMAGE_VERSION=${OS_VERSION}
fi

if [ ${#REPO_LIST[@]} -eq 0 ]; then
    # Either --repo or --local must be specified
    if [ "${LOCAL}" = "yes" ]; then
        REPO_LIST+=("local-std,http://${HOST}:8088${MY_WORKSPACE}/std/rpmbuild/RPMS")
        REPO_LIST+=("stx-distro,http://${HOST}:8088${MY_REPO}/cgcs-${OS}-repo/Binary")
    elif [ "${OPENSTACK_RELEASE}" != "master" ]; then
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
SRC_DOCKERFILE=${MY_SCRIPT_DIR}/stx-${OS}/Dockerfile.${OPENSTACK_RELEASE}
cp ${SRC_DOCKERFILE} ${BUILDDIR}/Dockerfile

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
IMAGE_NAME_LATEST=${DOCKER_REGISTRY}${DOCKER_USER}/stx-${OS}:${LATEST_TAG}

declare -a BUILD_ARGS
BUILD_ARGS+=(--build-arg RELEASE=${OS_VERSION})
BUILD_ARGS+=(--build-arg REPO_OPTS=${REPO_OPTS})

# Add proxy to docker build
if [ ! -z "$PROXY" ]; then
    BUILD_ARGS+=(--build-arg http_proxy=$PROXY)
fi
BUILD_ARGS+=(--tag ${IMAGE_NAME} ${BUILDDIR})

# Build base image
docker build "${BUILD_ARGS[@]}"
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

    if [ "$TAG_LATEST" = "yes" ]; then
        docker tag ${IMAGE_NAME} ${IMAGE_NAME_LATEST}
        echo "Pushing image: ${IMAGE_NAME_LATEST}"
        docker push ${IMAGE_NAME_LATEST}
        if [ $? -ne 0 ]; then
            echo "Failed running docker push command on latest" >&2
            exit 1
        fi
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

    if [ "$TAG_LATEST" = "yes" ]; then
        echo "Deleting image: ${IMAGE_NAME_LATEST}"
        docker image rm ${IMAGE_NAME_LATEST}
        if [ $? -ne 0 ]; then
            echo "Failed running docker image rm command" >&2
            exit 1
        fi
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

