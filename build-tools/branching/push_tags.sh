#!/bin/bash

if [ x"$1" = x ] ; then
    echo "ERROR: You must specify a name to push tags"
    exit 1
fi
tag=$1


echo "Finding subgits"
SUBGITS=`find . -type d -name ".git" | sed "s%/\.git$%%"`

# Go through all subgits and create the tag if it does not already exist
for subgit in $SUBGITS; do
    echo ""
    echo ""
    pushd $subgit > /dev/null

    echo "Creating tag $tag"
    git push origin $tag
    if [ $? != 0 ] ; then
        echo "ERROR: Could not exec: git push origin $tag"
        popd > /dev/null
        exit 1
    fi

    popd > /dev/null
done

