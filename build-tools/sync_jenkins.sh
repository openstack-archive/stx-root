#!/bin/bash

# This script "syncs" a local workspace up with a Jenkins build.
#
# The general flow of what it does is:
#    - checks out $MY_REPO to the same commits as the Jenkins build
#    - copies over Jenkins build artifacts in an order such that the timestamps
#      for SRPM/RPMS artifacts make sense (RPMS have later timestamps than SRPMS)
#
# The user can then check out changes since the Jenkins build, and build
# updated artifacts.  Typical use case would be
#   $ cd $MY_WORKSPACE
#   $ sync_jenkins.sh --latest
#   $ cd $MY_REPO
#   $ wrgit checkout CGCS_DEV_0017
#   $ cd $MY_WORKSPACE
#   $ build-pkgs
#
# Usage examples:
#    sync_jenkins.sh --help
#    sync_jenkins.sh --latest
#    sync_jenkins.sh yow-cgts4-lx:/localdisk/loadbuild/jenkins/CGCS_3.0_Centos_Build/2016-07-24_22-00-59"
#
#
# It is recommended that this tool be run with an initially empty workspace
# (or a workspace with only the build configuration file in it).
#
# Potential future improvements to this script
# - check for sane environment before doing anything
# - auto saving of the current branch of each git, and restoration to that point
#   after  pull
# - filter some packages (build-info, packages that depend on LICENSE, etc) from
#   pull

usage () {
    echo ""
    echo "Usage: "
    echo "    sync_jenkins.sh <--latest|--help|[path_to_jenkins_build]>"
    echo ""
    echo "  Examples:"
    echo "    sync_jenkins.sh --latest"
    echo "    Syncs to the latest Jenkins build on yow-cgts4-lx"
    echo ""
    echo "    sync_jenkins.sh yow-cgts4-lx:/localdisk/loadbuild/jenkins/CGCS_3.0_Centos_Build/2016-07-24_22-00-59"
    echo "    Syncs to a specfic Jenkins build"
    echo ""
}


# variables
BASEDIR=$MY_REPO
GITHASHFILE="LAST_COMMITS"
TMPFILE="$MY_WORKSPACE/export/temp.txt"
HELP=0

TEMP=`getopt -o h --long help,latest -n 'test.sh' -- "$@"`

if [ $? -ne 0 ]; then
    usage
    exit 1
fi

eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -h|--help) HELP=1 ; shift ;;
        --latest) JENKINSURL="yow-cgts4-lx:/localdisk/loadbuild/jenkins/latest_dev_stream/latest_build" ; shift ;;
        --) shift ; break ;;
    esac
done

if [ "x$JENKINSURL" == "x" ]; then
    JENKINSURL=$@
fi

if [ $HELP -eq 1 ]; then
    usage
    exit 0
fi

if [ "x$JENKINSURL" == "x" ]; then
    usage
    exit 1
fi

mkdir -p $MY_WORKSPACE/export $MY_WORKSPACE/std/rpmbuild/RPMS $MY_WORKSPACE/std/rpmbuild/SRPMS $MY_WORKSPACE/rt/rpmbuild/RPMS $MY_WORKSPACE/rt/rpmbuild/SRPMS
rsync $JENKINSURL/$GITHASHFILE $MY_WORKSPACE/$GITHASHFILE

if [ $? -ne 0 ]; then
    echo "Could not find $GITHASHFILE in $JENKINSURL -- aborting"
    exit 1
fi

pushd $MY_REPO > /dev/null

find . -type d -name ".git" | sed "s%/\.git$%%" > $TMPFILE

while read hashfile; do
    gitdir=`echo $hashfile | cut -d " " -f 1`
    gitcommit=`echo $hashfile | sed s/.*[[:space:]]//g`
    echo "doing dir $gitdir commit $gitcommit"

    pushd $gitdir >/dev/null
    git checkout $gitcommit
    popd
done < $MY_WORKSPACE/$GITHASHFILE

popd

pushd $MY_WORKSPACE

# clean stuff
for build_type in std rt; do
    rm -rf $MY_WORKSPACE/$build_type/rpmbuild/SRPMS
    rm -rf $MY_WORKSPACE/$build_type/rpmbuild/RPMS
    rm -rf $MY_WORKSPACE/$build_type/rpmbuild/inputs
    rm -rf $MY_WORKSPACE/$build_type/rpmbuild/srpm_assemble
done

# copy source rpms from jenkins
for build_type in std rt; do
    mkdir -p $MY_WORKSPACE/$build_type/rpmbuild/RPMS
    mkdir -p $MY_WORKSPACE/$build_type/rpmbuild/SRPMS
    rsync -r ${JENKINSURL}/$build_type/inputs $build_type/
    sleep 1
    rsync -r ${JENKINSURL}/$build_type/srpm_assemble $build_type/
    sleep 1
    rsync -r ${JENKINSURL}/$build_type/rpmbuild/SRPMS/* $MY_WORKSPACE/$build_type/rpmbuild/SRPMS
    sleep 1
    for sub_repo in cgcs-centos-repo cgcs-tis-repo cgcs-3rd-party-repo; do
        rsync ${JENKINSURL}/$build_type/$sub_repo.last_head $MY_WORKSPACE/$build_type
        if [ "$build_type" == "std" ]; then
            cp $MY_WORKSPACE/$build_type/$sub_repo.last_head $MY_REPO/$sub_repo/.last_head
        fi
    done
    sleep 1
    rsync -r ${JENKINSURL}/$build_type/results $build_type/
    sleep 1
    rsync -r ${JENKINSURL}/$build_type/rpmbuild/RPMS/* $MY_WORKSPACE/$build_type/rpmbuild/RPMS
done

popd
