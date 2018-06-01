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
   branch_check=`git branch -a --list $branch`
   if [ -z "$branch_check" ]
   then
      echo "Creating branch $branch"
      git checkout -b $branch
      if [ $? != 0 ] ; then
         echo "ERROR: Could not exec: git checkout -b $branch"
         popd > /dev/null
         exit 1
      fi
      # git push origin $branch:$branch
   else
      echo "Branch $branch already exists"
      git checkout $branch
   fi

   tag_check=`git tag -l $tag`
   if [ -z "$tag_check" ]
   then
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

