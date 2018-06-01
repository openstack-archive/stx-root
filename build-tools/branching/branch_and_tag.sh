#!/bin/bash

# The purpose of this script is to create branches and tags that follow a convention
# If the desired branch already exists, it is skipped.
# If the desired tag already exists, it is skipped.

OLD_TAG=vCGCS_DEV_0018
NEW_TAG=vCGCS_DEV_0019

OLD_BRANCH=CGCS_DEV_0018
NEW_BRANCH=CGCS_DEV_0019

if [ -z "$MY_REPO" ]; then 
  echo "MY_REPO is unset"
  exit 1
else
  echo "MY_REPO is set to '$MY_REPO'"
fi

if [ -d "$MY_REPO" ]; then 
  cd $MY_REPO
  echo "checking out and pulling old branch"
  wrgit checkout $OLD_BRANCH
  if [ $? -ne 0 ]; then
    echo "ERROR: wrgit checkout $OLD_BRANCH"
    exit 1
  fi

  wrgit pull
  if [ $? -ne 0 ]; then
    echo "ERROR: wrgit pull"
    exit 1
  fi
else
  echo "Could not change to diectory '$MY_REPO'"
  exit 1
fi

echo "Finding subgits"
SUBGITS=`find . -type d -name ".git" | sed "s%/\.git$%%"`

# Go through all subgits and create the NEW_BRANCH if it does not already exist
# Go through all subgits and create the NEW_TAG if it does not already exist
for subgit in $SUBGITS; do
 echo ""
 echo ""
 pushd $subgit > /dev/null
 git fetch
 git fetch --tags
 # check if destination branch already exists
 echo "$subgit"
 branch_check=`git branch -a --list $NEW_BRANCH`
 if [ -z "$branch_check" ]
 then
   echo "Creating $NEW_BRANCH"
   git checkout $OLD_BRANCH
   git checkout -b $NEW_BRANCH
   git push origin $NEW_BRANCH:$NEW_BRANCH
 else
   echo "$NEW_BRANCH already exists"
 fi
 tag_check=`git tag -l $NEW_TAG`
 if [ -z "$tag_check" ]
 then
   echo "Creating $NEW_TAG"
   # create tag
   git checkout $NEW_BRANCH
   git pull origin
   git tag $NEW_TAG
   git push origin $NEW_TAG
 else
   echo "$NEW_TAG already exists"
 fi

 popd > /dev/null
done

echo "All done.  branches and tags are pushed"








