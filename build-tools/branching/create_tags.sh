#!/bin/bash

if [ x"$1" = x ] ; then
    echo "ERROR: You must specify a name to create tags"
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

    tag_check=`git tag -l $tag`
    if [ -z "$tag_check" ]; then
        echo "Creating tag $tag"
        git tag $tag
        if [ $? != 0 ] ; then
            echo "ERROR: Could not exec: git tag $tag"
            popd > /dev/null
            exit 1
        fi
      # git push origin $tag
    else
        echo "Tag $tag already exists"
    fi

    popd > /dev/null
done

