#
# Copyright (c) 2018 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# A place for any functions relating to git, or the git hierarchy created
# by repo manifests.
#

#
# git_list <dir>:
#      Return a list of git root directories found under <dir>
#
git_list () {
    local DIR=${1}

    find "${DIR}" -type d -name '.git' -exec dirname {} \; | sort -V
}


# GIT_LIST: A list of root directories for all the gits under $MY_REPO/..
#           as absolute paths.
export GIT_LIST=$(git_list "$(dirname "${MY_REPO}")")


# GIT_LIST_REL: A list of root directories for all the gits under $MY_REPO/..
#               as relative paths.
export GIT_LIST_REL=$(for p in $GIT_LIST; do
                          echo .${p#$(dirname ${MY_REPO})};
                      done)


#
# git_list_containing_branch <dir> <branch>:
#      Return a list of git root directories found under <dir> and
#      having branch <branch>.  The branch need not be current branch.
#

git_list_containing_branch () {
    local DIR="${1}"
    local BRANCH="${2}"

    local d
    for d in $(git_list "${DIR}"); do
        (
        cd "$d"
        git branch --all | grep -q "$BRANCH"
        if [ $? -eq 0 ]; then
            echo "$d"
        fi
        )
    done
}


#
# git_list_containing_tag <dir> <tag>:
#      Return a list of git root directories found under <dir> and
#      having tag <tag>.
#

git_list_containing_tag () {
    local DIR="${1}"
    local TAG="${2}"

    local d
    for d in $(git_list "${DIR}"); do
        (
        cd "$d"
        git tag | grep -q "$TAG"
        if [ $? -eq 0 ]; then
            echo "$d"
        fi
        )
    done
}


#
# git_context:
#     Returns a bash script that can be used to recreate the current git context,
#
# Note: all paths are relative to $MY_REPO/..
#

git_context () {
    (
    cd $MY_REPO
    for d in $GIT_LIST_REL; do
        (
        cd ${d}
        echo -n "(cd ${d} && git checkout -f "
        echo "$(git rev-list HEAD -1))"
        )
    done
    )
}
