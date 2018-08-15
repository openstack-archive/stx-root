#
# Copyright (c) 2018 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# A place for any functions relating to git, or the git hierarchy created 
# by repo manifests.
#

# GIT_LIST: A list of root directories for all the gits under $MY_REPO
export GIT_LIST=$(find $MY_REPO -type d -name '.git' -exec dirname {} \;)

