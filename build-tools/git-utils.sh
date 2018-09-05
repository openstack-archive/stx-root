#
# Copyright (c) 2018 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# A place for any functions relating to git, or the git hierarchy created
# by repo manifests.
#

git_ctx_root_dir () {
    dirname "${MY_REPO}"
}

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
export GIT_LIST=$(git_list "$(git_ctx_root_dir)")


# GIT_LIST_REL: A list of root directories for all the gits under $MY_REPO/..
#               as relative paths.
export GIT_LIST_REL=$(for p in $GIT_LIST; do echo .${p#$(git_ctx_root_dir)}; done)


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
    cd $(git_ctx_root_dir)

    local d
    for d in $GIT_LIST_REL; do
        (
        cd ${d}
        echo -n "(cd ${d} && git checkout -f "
        echo "$(git rev-list HEAD -1))"
        )
    done
    )
}

#
# git_test_context <context>:
#
# Test if all commits referenced in the context are present
# in the history of the gits in their current checkout state.
#
# Returns: 0 = context is present in git history
#          1 = At least one element of context is not present
#          2 = error
#
git_test_context () {
    local context="$1"
    local query=""
    local target_hits=0
    local actual_hits=0

    if [ ! -f "$context" ]; then
        return 2
    fi

    query=$(mktemp "/tmp/git_test_context_XXXXXX")
    if [ "$query" == "" ]; then
        return 2
    fi

    # Transform a checkout context into a query that prints
    # all the commits that are found in the git history.
    #
    # Limit search to last 500 commits in the interest of speed.
    # I don't expect to be using contexts more than a few weeks old.
    cat "$context" | \
        sed "s#checkout -f \([a-e0-9]*\)#rev-list --max-count=500 HEAD | \
        grep \1#" > $query

    target_hits=$(cat "$context" | wc -l)
    actual_hits=$(cd $(git_ctx_root_dir); source $query | wc -l)
    \rm $query

    if [ $actual_hits -eq $target_hits ]; then
        return 0
    fi

    return 1
}
