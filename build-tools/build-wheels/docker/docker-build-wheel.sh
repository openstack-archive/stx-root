#!/bin/bash
#
# Copyright (c) 2018 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This utility builds a set of python wheels for upstream packages,
# reading a source list from wheels.cfg
#

CFGFILE=/wheels.cfg
OUTPUTDIR=/wheels
FAILED_LOG=$OUTPUTDIR/failed.lst

#
# Function to log the start of a build
#
function startlog {
    cat <<EOF

############################################################
Building $1
############################################################
EOF
}

#
# Function to find the line number for the first import
function first_import_line {
    grep -nE '^(from|import)' setup.py \
        | grep -v __future__ \
        | head -1 \
        | sed 's/:.*//'
}

#
# Function to update the python module to use setuptools.setup,
# in order to support building the wheel.
# This function is only called if fix_setup is specified for the
# module in wheels.cfg
#
function fix_setup {
    echo "########### Running fix_setup"

    # bugtrack_url is not supported by setuptools.setup
    grep -q '^[[:space:]]*bugtrack_url=' setup.py
    if [ $? -eq 0 ]; then
        sed -i '/^[[:space:]]*bugtrack_url=/d' setup.py
    fi

    # If setuptools.setup is already being imported, nothing to do.
    grep -q '^from setuptools import setup' setup.py
    if [ $? -eq 0 ]; then
        return
    fi

    # Look for various ways distutils.core.setup is being imported,
    # and replace it with setuptools.setup, inserting the new import
    # ahead of the first existing import.

    grep -q '^from distutils.core import .*setup,' setup.py
    if [ $? -eq 0 ]; then
        cp setup.py setup.py.orig
        sed -i 's/^\(from distutils.core import .*\)setup,/\1/' setup.py
        line=$(first_import_line)
        sed -i "${line}i from setuptools import setup" setup.py
        return
    fi

    grep -q '^from distutils.core import setup' setup.py
    if [ $? -eq 0 ]; then
        cp setup.py setup.py.orig
        line=$(first_import_line)
        sed -i '/^from distutils.core import setup/d' setup.py
        sed -i "${line}i from setuptools import setup" setup.py
        return
    fi

    grep -q '^from distutils.core import .*setup' setup.py
    if [ $? -eq 0 ]; then
        cp setup.py setup.py.orig
        line=$(first_import_line)
        sed -i 's/^\(from distutils.core import .*\), setup/\1/' setup.py
        sed -i "${line}i from setuptools import setup" setup.py
        return
    fi

    grep -q '^import distutils.core as duc' setup.py
    if [ $? -eq 0 ]; then
        cp setup.py setup.py.orig
        line=$(first_import_line)
        sed -i "${line}i from setuptools import setup" setup.py
        sed -i 's/duc.setup/setup/' setup.py
        return
    fi

    # Insert it
    cp setup.py setup.py.orig
    line=$(first_import_line)
    sed -i 's/^\(from distutils.core import .*\), setup/\1/' setup.py
    sed -i "${line}i from setuptools import setup" setup.py

}

#
# Function to use git to clone the module source and build a wheel.
#
function from_git {
    sed 's/#.*//' $CFGFILE | awk -F '|' '$2 == "git" { print $0; }' | \
    while IFS='|' read wheelname stype gitrepo basedir branch fix; do
        startlog $wheelname

        if [ -f $OUTPUTDIR/$wheelname ]; then
            echo "$wheelname already exists"
            continue
        fi

        git clone $gitrepo
        if [ $? -ne 0 ]; then
            echo "Failure running: git clone $gitrepo"
            echo $wheelname >> $FAILED_LOG
            continue
        fi

        pushd $basedir
        if [ $? -ne 0 ]; then
            echo "Failure running: pushd $basedir"
            echo $wheelname >> $FAILED_LOG
            continue
        fi

        git checkout $branch
        if [ $? -ne 0 ]; then
            echo "Failure running: git checkout $branch"
            echo $wheelname >> $FAILED_LOG
            continue
        fi

        if [ "$fix" == "fix_setup" ]; then
            fix_setup
        fi

        # Build the wheel
        python setup.py bdist_wheel
        cp dist/$wheelname $OUTPUTDIR || echo $wheelname >> $FAILED_LOG
        popd
    done
}

#
# Function to download a source tarball and build a wheel.
#
function from_tar {
    sed 's/#.*//' $CFGFILE | awk -F '|' '$2 == "tar" { print $0; }' | \
    while IFS='|' read wheelname stype wgetsrc basedir fix; do
        startlog $wheelname

        if [ -f $OUTPUTDIR/$wheelname ]; then
            echo "$wheelname already exists"
            continue
        fi

        tarball=$(basename $wgetsrc)
        if [[ $tarball =~ gz$ ]]; then
            taropts="xzf"
        elif [[ $tarball =~ bz2$ ]]; then
            taropts="xjf"
        else
            taropts="xf"
        fi

        wget $wgetsrc
        if [ $? -ne 0 ]; then
            echo "Failure running: wget $wgetsrc"
            echo $wheelname >> $FAILED_LOG
            continue
        fi

        tar $taropts $(basename $wgetsrc)
        if [ $? -ne 0 ]; then
            echo "Failure running: tar $taropts $(basename $wgetsrc)"
            echo $wheelname >> $FAILED_LOG
            continue
        fi

        pushd $basedir
        if [ $? -ne 0 ]; then
            echo "Failure running: pushd $basedir"
            echo $wheelname >> $FAILED_LOG
            continue
        fi

        if [ "$fix" == "fix_setup" ]; then
            fix_setup
        fi

        # Build the wheel
        python setup.py bdist_wheel
        cp dist/$wheelname $OUTPUTDIR || echo $wheelname >> $FAILED_LOG
        popd
    done
}

#
# Function to download a source zip file and build a wheel.
#
function from_zip {
    sed 's/#.*//' $CFGFILE | awk -F '|' '$2 == "zip" { print $0; }' | \
    while IFS='|' read wheelname stype wgetsrc basedir fix; do
        startlog $wheelname

        if [ -f $OUTPUTDIR/$wheelname ]; then
            echo "$wheelname already exists"
            continue
        fi

        wget $wgetsrc
        if [ $? -ne 0 ]; then
            echo "Failure running: wget $wgetsrc"
            echo $wheelname >> $FAILED_LOG
            continue
        fi

        unzip $(basename $wgetsrc)
        if [ $? -ne 0 ]; then
            echo "Failure running: unzip $(basename $wgetsrc)"
            echo $wheelname >> $FAILED_LOG
            continue
        fi

        pushd $basedir
        if [ $? -ne 0 ]; then
            echo "Failure running: pushd $basedir"
            echo $wheelname >> $FAILED_LOG
            continue
        fi

        if [ "$fix" == "fix_setup" ]; then
            fix_setup
        fi

        # Build the wheel
        python setup.py bdist_wheel
        cp dist/$wheelname $OUTPUTDIR || echo $wheelname >> $FAILED_LOG
        popd
    done
}

#
# Function to download an existing wheel from pypi.
#
function from_pypi {
    sed 's/#.*//' $CFGFILE | awk -F '|' '$2 == "pypi" { print $0; }' | \
    while IFS='|' read wheelname stype wgetsrc; do
        startlog $wheelname

        if [ -f $OUTPUTDIR/$wheelname ]; then
            echo "$wheelname already exists"
            continue
        fi

        wget $wgetsrc
        if [ $? -ne 0 ]; then
            echo "Failure running: wget $wgetsrc"
            echo $wheelname >> $FAILED_LOG
            continue
        fi

        cp $wheelname $OUTPUTDIR || echo $wheelname >> $FAILED_LOG
    done
}

rm -f $FAILED_LOG
mkdir -p /build-wheels
cd /build-wheels
from_git
from_tar
from_zip
from_pypi

if [ -f $FAILED_LOG ]; then
    let -i failures=$(cat $FAILED_LOG | wc -l)

    cat <<EOF
############################################################
The following module(s) failed to build:
$(cat $FAILED_LOG)

Summary:
${failures} build failure(s).
EOF
    exit 1
fi

cat <<EOF
############################################################
All wheels have been successfully built.
EOF

exit 0

