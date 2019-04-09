#!/bin/bash
#
# Copyright (c) 2018-2019 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This utility builds the StarlingX container images
#

MY_SCRIPT_DIR=$(dirname $(readlink -f $0))

source ${MY_SCRIPT_DIR}/../build-wheels/utils.sh

# Required env vars
if [ -z "${MY_WORKSPACE}" -o -z "${MY_REPO}" ]; then
    echo "Environment not setup for builds" >&2
    exit 1
fi

source ${MY_REPO}/build-tools/git-utils.sh

SUPPORTED_OS_ARGS=('centos')
OS=centos
BUILD_STREAM=stable
IMAGE_VERSION=$(date --utc '+%Y.%m.%d.%H.%M') # Default version, using timestamp
PREFIX=dev
LATEST_PREFIX=""
PUSH=no
PROXY=""
DOCKER_USER=${USER}
DOCKER_REGISTRY=
BASE=
WHEELS=
CLEAN=no
TAG_LATEST=no
TAG_LIST_FILE=
TAG_LIST_LATEST_FILE=
declare -a ONLY
declare -a SKIP
declare -i MAX_ATTEMPTS=1

function usage {
    cat >&2 <<EOF
Usage:
$(basename $0)

Options:
    --os:         Specify base OS (valid options: ${SUPPORTED_OS_ARGS[@]})
    --version:    Specify version for output image
    --stream:     Build stream, stable or dev (default: stable)
    --base:       Specify base docker image (required option)
    --wheels:     Specify path to wheels tarball or image, URL or docker tag (required option)
    --push:       Push to docker repo
    --proxy:      Set proxy <URL>:<PORT>
    --user:       Docker repo userid
    --registry:   Docker registry
    --prefix:     Prefix on the image tag (default: dev)
    --latest:     Add a 'latest' tag when pushing
    --latest-prefix: Alternative prefix on the latest image tag
    --clean:      Remove image(s) from local registry
    --only <image> : Only build the specified image(s). Multiple images
                     can be specified with a comma-separated list, or with
                     multiple --only arguments.
    --skip <image> : Skip building the specified image(s). Multiple images
                     can be specified with a comma-separated list, or with
                     multiple --skip arguments.
    --attempts:   Max attempts, in case of failure (default: 1)


EOF
}

function is_in {
    local search=$1
    shift

    for v in $*; do
        if [ "${search}" = "${v}" ]; then
            return 0
        fi
    done
    return 1
}

function is_empty {
    test $# -eq 0
}

function get_loci {
    # Use a specific HEAD of loci, to provide a stable builder
    local LOCI_REF="432503259f5e624afdabd9dacc9d9b367dd95e96"

    ORIGWD=${PWD}

    if [ ! -d ${WORKDIR}/loci ]; then
        cd ${WORKDIR}
        git clone --recursive https://github.com/openstack/loci.git
        if [ $? -ne 0 ]; then
            echo "Failed to clone loci. Aborting..." >&2
            return 1
        fi

        cd loci
        git checkout ${LOCI_REF}
        if [ $? -ne 0 ]; then
            echo "Failed to checkout loci base ref: ${LOCI_REF}" >&2
            echo "Aborting..." >&2
            return 1
        fi
    else
        cd ${WORKDIR}/loci
        local cur_head
        cur_head=$(git rev-parse HEAD)

        if [ "${cur_head}" != "${LOCI_REF}" ]; then
            git fetch
            if [ $? -ne 0 ]; then
                echo "Failed to fetch loci. Aborting..." >&2
                return 1
            fi

            git checkout ${LOCI_REF}
            if [ $? -ne 0 ]; then
                echo "Failed to checkout loci base ref: ${LOCI_REF}" >&2
                echo "Aborting..." >&2
                return 1
            fi
        fi
    fi

    cd ${ORIGPWD}

    return 0
}

function update_image_record {
    # Update the image record file with a new/updated entry
    local LABEL=$1
    local TAG=$2
    local FILE=$3

    grep -q "/${LABEL}:" ${FILE}
    if [ $? -eq 0 ]; then
        # Update the existing record
        sed -i "s#.*/${LABEL}:.*#${TAG}#" ${FILE}
    else
        # Add a new record
        echo "${TAG}" >> ${FILE}
    fi
}

function post_build {
    #
    # Common utility function called from image build functions to run post-build steps.
    #
    local image_build_file=$1
    local LABEL=$2
    local build_image_name=$3

    # Get additional supported args
    #
    # To avoid polluting the environment and impacting
    # other builds, we're going to explicitly grab specific
    # variables from the directives file. While this does
    # mean the file is sourced repeatedly, it ensures we
    # don't get junk.
    local CUSTOMIZATION
    CUSTOMIZATION=$(source ${image_build_file} && echo ${CUSTOMIZATION})

    if [ -n "${CUSTOMIZATION}" ]; then
        docker run --name ${USER}_update_img ${build_image_name} bash -c "${CUSTOMIZATION}"
        if [ $? -ne 0 ]; then
            echo "Failed to add customization for ${LABEL}... Aborting"
            RESULTS_FAILED+=(${LABEL})
            docker rm ${USER}_update_img
            return 1
        fi

        docker commit --change='CMD ["bash"]' ${USER}_update_img ${build_image_name}
        if [ $? -ne 0 ]; then
            echo "Failed to commit customization for ${LABEL}... Aborting"
            RESULTS_FAILED+=(${LABEL})
            docker rm ${USER}_update_img
            return 1
        fi

        docker rm ${USER}_update_img
    fi

    if [ "${OS}" = "centos" ]; then
        # Record python modules and packages
        docker run --rm ${build_image_name} bash -c 'rpm -qa | sort' \
            > ${WORKDIR}/${LABEL}-${OS}-${BUILD_STREAM}.rpmlst
        docker run --rm ${build_image_name} bash -c 'pip freeze 2>/dev/null | sort' \
            > ${WORKDIR}/${LABEL}-${OS}-${BUILD_STREAM}.piplst
    fi

    RESULTS_BUILT+=(${build_image_name})

    if [ "${PUSH}" = "yes" ]; then
        local push_tag="${DOCKER_REGISTRY}${DOCKER_USER}/${LABEL}:${IMAGE_TAG}"
        docker tag ${build_image_name} ${push_tag}
        docker push ${push_tag}
        RESULTS_PUSHED+=(${push_tag})

        update_image_record ${LABEL} ${push_tag} ${TAG_LIST_FILE}

        if [ "$TAG_LATEST" = "yes" ]; then
            local latest_tag="${DOCKER_REGISTRY}${DOCKER_USER}/${LABEL}:${IMAGE_TAG_LATEST}"
            docker tag ${push_tag} ${latest_tag}
            docker push ${latest_tag}
            RESULTS_PUSHED+=(${latest_tag})

            update_image_record ${LABEL} ${latest_tag} ${TAG_LIST_LATEST_FILE}
        fi
    fi
}

function build_image_loci {
    local image_build_file=$1

    # Get the supported args
    #
    # To avoid polluting the environment and impacting
    # other builds, we're going to explicitly grab specific
    # variables from the directives file. While this does
    # mean the file is sourced repeatedly, it ensures we
    # don't get junk.
    local LABEL
    LABEL=$(source ${image_build_file} && echo ${LABEL})
    local PROJECT
    PROJECT=$(source ${image_build_file} && echo ${PROJECT})
    local PROJECT_REPO
    PROJECT_REPO=$(source ${image_build_file} && echo ${PROJECT_REPO})
    local PROJECT_REF
    PROJECT_REF=$(source ${image_build_file} && echo ${PROJECT_REF})
    local PIP_PACKAGES
    PIP_PACKAGES=$(source ${image_build_file} && echo ${PIP_PACKAGES})
    local DIST_PACKAGES
    DIST_PACKAGES=$(source ${image_build_file} && echo ${DIST_PACKAGES})
    local PROFILES
    PROFILES=$(source ${image_build_file} && echo ${PROFILES})

    if is_in ${PROJECT} ${SKIP[@]} || is_in ${LABEL} ${SKIP[@]}; then
        echo "Skipping ${LABEL}"
        return 0
    fi

    if ! is_empty ${ONLY[@]} && ! is_in ${PROJECT} ${ONLY[@]} && ! is_in ${LABEL} ${ONLY[@]}; then
        echo "Skipping ${LABEL}"
        return 0
    fi

    echo "Building ${LABEL}"

    local -a BUILD_ARGS=
    BUILD_ARGS=(--build-arg PROJECT=${PROJECT})
    BUILD_ARGS+=(--build-arg PROJECT_REPO=${PROJECT_REPO})
    BUILD_ARGS+=(--build-arg FROM=${BASE})
    BUILD_ARGS+=(--build-arg WHEELS=${WHEELS})
    if [ ! -z "$PROXY" ]; then
        BUILD_ARGS+=(--build-arg http_proxy=$PROXY)
    fi

    if [ -n "${PROJECT_REF}" ]; then
        BUILD_ARGS+=(--build-arg PROJECT_REF=${PROJECT_REF})
    fi

    if [ -n "${PIP_PACKAGES}" ]; then
        BUILD_ARGS+=(--build-arg PIP_PACKAGES="${PIP_PACKAGES}")
    fi

    if [ -n "${DIST_PACKAGES}" ]; then
        BUILD_ARGS+=(--build-arg DIST_PACKAGES="${DIST_PACKAGES}")
    fi

    if [ -n "${PROFILES}" ]; then
        BUILD_ARGS+=(--build-arg PROFILES="${PROFILES}")
    fi

    local build_image_name="${USER}/${LABEL}:${IMAGE_TAG_BUILD}"

    with_retries ${MAX_ATTEMPTS} docker build ${WORKDIR}/loci --no-cache \
        "${BUILD_ARGS[@]}" \
        --tag ${build_image_name}  2>&1 | tee ${WORKDIR}/docker-${LABEL}-${OS}-${BUILD_STREAM}.log
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "Failed to build ${LABEL}... Aborting"
        RESULTS_FAILED+=(${LABEL})
        return 1
    fi

    if [ ${OS} = "centos" ]; then
        # For images with apache, we need a workaround for paths
        echo "${PROFILES}" | grep -q apache
        if [ $? -eq 0 ]; then
            docker run --name ${USER}_update_img ${build_image_name} bash -c '\
                ln -s /var/log/httpd /var/log/apache2 && \
                ln -s /var/run/httpd /var/run/apache2 && \
                ln -s /etc/httpd /etc/apache2 && \
                ln -s /etc/httpd/conf.d /etc/apache2/conf-enabled && \
                ln -s /etc/httpd/conf.modules.d /etc/apache2/mods-available && \
                ln -s /usr/sbin/httpd /usr/sbin/apache2 && \
                ln -s /etc/httpd/conf.d /etc/apache2/sites-enabled \
            '
            if [ $? -ne 0 ]; then
                echo "Failed to add apache workaround for ${LABEL}... Aborting"
                RESULTS_FAILED+=(${LABEL})
                docker rm ${USER}_update_img
                return 1
            fi

            docker commit --change='CMD ["bash"]' ${USER}_update_img ${build_image_name}
            if [ $? -ne 0 ]; then
                echo "Failed to commit apache workaround for ${LABEL}... Aborting"
                RESULTS_FAILED+=(${LABEL})
                docker rm ${USER}_update_img
                return 1
            fi

            docker rm ${USER}_update_img
        fi
    fi

    post_build ${image_build_file} ${LABEL} ${build_image_name}
}

function build_image_docker {
    local image_build_file=$1

    # Get the supported args
    #
    local LABEL
    LABEL=$(source ${image_build_file} && echo ${LABEL})

    if is_in ${PROJECT} ${SKIP[@]} || is_in ${LABEL} ${SKIP[@]}; then
        echo "Skipping ${LABEL}"
        return 0
    fi

    if ! is_empty ${ONLY[@]} && ! is_in ${PROJECT} ${ONLY[@]} && ! is_in ${LABEL} ${ONLY[@]}; then
        echo "Skipping ${LABEL}"
        return 0
    fi

    echo "Building ${LABEL}"

    local docker_src
    docker_src=$(dirname ${image_build_file})/docker

    # Check for a Dockerfile
    if [ ! -f ${docker_src}/Dockerfile ]; then
        echo "${docker_src}/Dockerfile not found" >&2
        RESULTS_FAILED+=(${LABEL})
        return 1
    fi

    # Possible design option: Make a copy of the docker_src dir in BUILDDIR

    local build_image_name="${USER}/${LABEL}:${IMAGE_TAG_BUILD}"

    local -a BASE_BUILD_ARGS
    BASE_BUILD_ARGS+=(${docker_src} --no-cache)
    BASE_BUILD_ARGS+=(--build-arg "BASE=${BASE}")
    if [ ! -z "$PROXY" ]; then
        BASE_BUILD_ARGS+=(--build-arg http_proxy=$PROXY)
    fi
    BASE_BUILD_ARGS+=(--tag ${build_image_name})
    with_retries ${MAX_ATTEMPTS} docker build ${BASE_BUILD_ARGS[@]} 2>&1 | tee ${WORKDIR}/docker-${LABEL}-${OS}-${BUILD_STREAM}.log

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "Failed to build ${LABEL}... Aborting"
        RESULTS_FAILED+=(${LABEL})
        return 1
    fi

    post_build ${image_build_file} ${LABEL} ${build_image_name}
}

function build_image {
    local image_build_file=$1

    # Get the builder
    local BUILDER
    BUILDER=$(source ${image_build_file} && echo ${BUILDER})

    case ${BUILDER} in
        loci)
            build_image_loci ${image_build_file}
            return $?
            ;;
        docker)
            build_image_docker ${image_build_file}
            return $?
            ;;
        *)
            echo "Unsupported BUILDER in ${image_build_file}: ${BUILDER}" >&2
            return 1
            ;;
    esac
}

OPTS=$(getopt -o h -l help,os:,version:,release:,stream:,push,proxy:,user:,registry:,base:,wheels:,only:,skip:,prefix:,latest,latest-prefix:,clean,attempts: -- "$@")
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
        --base)
            BASE=$2
            shift 2
            ;;
        --os)
            OS=$2
            shift 2
            ;;
        --wheels)
            WHEELS=$2
            shift 2
            ;;
        --version)
            IMAGE_VERSION=$2
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
        --prefix)
            PREFIX=$2
            shift 2
            ;;
        --latest-prefix)
            LATEST_PREFIX=$2
            shift 2
            ;;
        --push)
            PUSH=yes
            shift
            ;;
        --proxy)
            PROXY=$2
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
        --only)
            # Read comma-separated values into array
            ONLY+=(${2//,/ })
            shift 2
            ;;
        --skip)
            # Read comma-separated values into array
            SKIP+=(${2//,/ })
            shift 2
            ;;
        --latest)
            TAG_LATEST=yes
            shift
            ;;
        --attempts)
            MAX_ATTEMPTS=$2
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

if [ -z "${WHEELS}" ]; then
    echo "Path to wheels tarball must be specified with --wheels option." >&2
    exit 1
fi

if [ -z "${BASE}" ]; then
    echo "Base image must be specified with --base option." >&2
    exit 1
fi

IMAGE_TAG="${OS}-${BUILD_STREAM}"
IMAGE_TAG_LATEST="${IMAGE_TAG}-latest"

if [ -n "${LATEST_PREFIX}" ]; then
    IMAGE_TAG_LATEST="${LATEST_PREFIX}-${IMAGE_TAG_LATEST}"
elif [ -n "${PREFIX}" ]; then
    IMAGE_TAG_LATEST="${PREFIX}-${IMAGE_TAG_LATEST}"
fi

if [ -n "${PREFIX}" ]; then
    IMAGE_TAG="${PREFIX}-${IMAGE_TAG}"
fi

IMAGE_TAG_BUILD="${IMAGE_TAG}-build"

if [ -n "${IMAGE_VERSION}" ]; then
    IMAGE_TAG="${IMAGE_TAG}-${IMAGE_VERSION}"
fi

WORKDIR=${MY_WORKSPACE}/std/build-images
mkdir -p ${WORKDIR}
if [ $? -ne 0 ]; then
    echo "Failed to create ${WORKDIR}" >&2
    exit 1
fi

TAG_LIST_FILE=${WORKDIR}/images-${OS}-${BUILD_STREAM}-versioned.lst
TAG_LIST_LATEST_FILE=${WORKDIR}/images-${OS}-${BUILD_STREAM}-latest.lst
if [ "${PUSH}" = "yes" ]; then
    if is_empty ${ONLY[@]} && is_empty ${SKIP[@]}; then
        # Reset image record files, since we're building everything
        echo -n > ${TAG_LIST_FILE}

        if [ "$TAG_LATEST" = "yes" ]; then
            echo -n > ${TAG_LIST_LATEST_FILE}
        fi
    fi
fi

# Check to see if the BASE image is already pulled
docker images --format '{{.Repository}}:{{.Tag}}' ${BASE} | grep -q "^${BASE}$"
BASE_IMAGE_PRESENT=$?

# Pull the image anyway, to ensure it's up to date
docker pull ${BASE}

# Download loci, if needed.
get_loci
if [ $? -ne 0 ]; then
    # Error is reported by the function already
    exit 1
fi

# Find the directives files
for image_build_inc_file in $(find ${GIT_LIST} -maxdepth 1 -name "${OS}_${BUILD_STREAM}_docker_images.inc"); do
    basedir=$(dirname ${image_build_inc_file})
    for image_build_dir in $(sed -e 's/#.*//' ${image_build_inc_file} | sort -u); do
        for image_build_file in ${basedir}/${image_build_dir}/${OS}/*.${BUILD_STREAM}_docker_image; do
            # Failures are reported by the build functions
            build_image ${image_build_file}
        done
    done
done

if [ "${CLEAN}" = "yes" -a ${#RESULTS_BUILT[@]} -gt 0 ]; then
    # Delete the images
    echo "Deleting images"
    docker image rm ${RESULTS_BUILT[@]} ${RESULTS_PUSHED[@]}
    if [ $? -ne 0 ]; then
        # We don't want to fail the overall build for this, so just log it
        echo "Failed to clean up images" >&2
    fi

    if [ ${BASE_IMAGE_PRESENT} -ne 0 ]; then
        # The base image was not already present, so delete it
        echo "Removing docker image ${BASE}"
        docker image rm ${BASE}
        if [ $? -ne 0 ]; then
            echo "Failed to delete base image from docker" >&2
        fi
    fi
fi

RC=0
if [ ${#RESULTS_BUILT[@]} -gt 0 ]; then
    echo "#######################################"
    echo
    echo "The following images were built:"
    for i in ${RESULTS_BUILT[@]}; do
        echo $i
    done | sort

    if [ ${#RESULTS_PUSHED[@]} -gt 0 ]; then
        echo
        echo "The following tags were pushed:"
        for i in ${RESULTS_PUSHED[@]}; do
            echo $i
        done | sort
    fi
fi

if [ ${#RESULTS_FAILED[@]} -gt 0 ]; then
    echo
    echo "#######################################"
    echo
    echo "There were ${#RESULTS_FAILED[@]} failures:"
    for i in ${RESULTS_FAILED[@]}; do
        echo $i
    done | sort
    RC=1
fi

exit ${RC}

