
#!/bin/bash

if [ x"$1" = x ] ; then
    echo "ERROR: You must specify a name to create branches and tags"
    exit 1
fi
branch=$1
tag="v$branch"



echo "Finding subgits"
SUBGITS=`find . -type d -name ".git" | sed "s%/\.git$%%"`

# Go through all subgits and create the branch and tag if they does not already exist
for subgit in $SUBGITS; do
    echo ""
    echo ""
    pushd $subgit > /dev/null

   # check if destination branch already exists
    echo "$subgit"
    echo "Pushing branch $branch"
    git push origin $branch:$branch
    if [ $? != 0 ] ; then
        echo "ERROR: Could not exec: git push origin $branch:$branch"
        popd > /dev/null
        exit 1
    fi

    echo "Pushing tag $tag"
    git push origin $tag
    if [ $? != 0 ] ; then
        echo "ERROR: Could not exec: git push origin $tag"
        popd > /dev/null
        exit 1
    fi

    popd > /dev/null
done

