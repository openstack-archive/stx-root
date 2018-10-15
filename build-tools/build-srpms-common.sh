#
# Copyright (c) 2018 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Functions common to build-srpm-serial and build-srpm-parallel.
#

SRC_BUILD_TYPE_SRPM="srpm"
SRC_BUILD_TYPE_SPEC="spec"
SRC_BUILD_TYPES="$SRC_BUILD_TYPE_SRPM $SRC_BUILD_TYPE_SPEC"


str_lst_contains() {
    TARGET="$1"
    LST="$2"

    if [[ $LST =~ (^|[[:space:]])$TARGET($|[[:space:]]) ]] ; then
        return 0
    else
        return 1
    fi
}


#
# capture_md5sum_from_input_vars <src-build-type> <srpm-or-spec-path> <work-dir>
#
# Returns md5 data for all input files of a src.rpm.
# Assumes PKG_BASE, ORIG_SRPM_PATH have been defined and the
# build_srpm.data file has already been sourced.
#
# Arguments:
#   src-build-type: Any single value from $SRC_BUILD_TYPES.
#                   e.g. 'srpm' or 'spec'
#   srpm-or-spec-path: Absolute path to an src.rpm, or to a
#                      spec file.
#   work-dir: Optional working directory.  If a path is
#             specified but does not exist, it will be created.
#
# Returns: output of md5sum command with canonical path names
#
md5sums_from_input_vars () {
    local SRC_BUILD_TYPE="$1"
    local SRPM_OR_SPEC_PATH="$2"
    local WORK_DIR="$3"

    local TMP_FLAG=0
    local LINK_FILTER='[/]stx[/]downloads[/]'

    if ! str_lst_contains "$SRC_BUILD_TYPE" "$SRC_BUILD_TYPES" ; then
        >&2  echo "ERROR: $FUNCNAME (${LINENO}): invalid arg: SRC_BUILD_TYPE='$SRC_BUILD_TYPE'"
        return 1
    fi

    if [ -z $WORK_DIR ]; then
        WORK_DIR=$(mktemp -d /tmp/${FUNCNAME}_XXXXXX)
        if [ $? -ne 0 ]; then
            >&2  echo "ERROR: $FUNCNAME (${LINENO}): mktemp -d /tmp/${FUNCNAME}_XXXXXX"
            return 1
        fi
        TMP_FLAG=1
    else
        mkdir -p "$WORK_DIR"
        if [ $? -ne 0 ]; then
            >&2  echo "ERROR: $FUNCNAME (${LINENO}): mkdir -p '$WORK_DIR'"
            return 1
        fi
    fi

    local INPUT_FILES="$WORK_DIR/srpm_input.files"
    local INPUT_LINKS="$WORK_DIR/srpm_input.links"
    local INPUT_FILES_SORTED="$WORK_DIR/srpm_sorted_input.files"

    if [ -f "$INPUT_LINKS" ]; then
        \rm -f "$INPUT_LINKS"
    fi

    # Create lists of input files (INPUT_FILES) and symlinks (INPUT_LINKS).
    # First elements are absolute paths...
    find "$PKG_BASE" -type f > $INPUT_FILES
    if [ $? -ne 0 ]; then
        >&2  echo "ERROR: $FUNCNAME (${LINENO}): find '$PKG_BASE' -type f"
        return 1
    fi

    if [ "$SRC_BUILD_TYPE" == "$SRC_BUILD_TYPE_SRPM" ]; then
        find "$SRPM_OR_SPEC_PATH" -type f >> $INPUT_FILES
        if [ $? -ne 0 ]; then
            >&2  echo "ERROR: $FUNCNAME (${LINENO}): find '$SRPM_OR_SPEC_PATH' -type f"
            return 1
        fi
    fi

    # ...additional elements are based on values already sourced from
    # build_srpm.data (COPY_LIST, SRC_DIR, COPY_LIST_TO_TAR, OPT_DEP_LIST)
    # and may be relative to $PKG_BASE
    #
    # Use a subshell so any directory changes have no lastin effect.
    (
        cd $PKG_BASE
        if [ "x$COPY_LIST" != "x" ]; then
            ABS_COPY_LIST=$(readlink -f $COPY_LIST)
            if [ $? -ne 0 ]; then
                >&2  echo "ERROR: $FUNCNAME (${LINENO}): readlink -f '$COPY_LIST' -type f"
                return 1
            fi

            find $ABS_COPY_LIST -type f >> $INPUT_FILES
            if [ $? -ne 0 ]; then
                >&2  echo "ERROR: $FUNCNAME (${LINENO}): find '$ABS_COPY_LIST' -type f"
                return 1
            fi

            # Treat most links normally
            find $ABS_COPY_LIST -type l | grep -v "$LINK_FILTER" >> $INPUT_FILES

            # Links in the downloads directory likely point outside of $MY_REPO
            # and might not be 'portable' from a build avoidance prespective.
            # We'll treat these specially.
            find $ABS_COPY_LIST -type l | grep "$LINK_FILTER" >> $INPUT_LINKS
        fi

        if [ "$SRC_BUILD_TYPE" == "$SRC_BUILD_TYPE_SPEC" ]; then
            if [ "x$SRC_DIR" != "x" ]; then
                if [ -d "$SRC_DIR" ]; then
                    find $(readlink -f "$SRC_DIR") -type f | grep -v '[/][.]git$' | grep -v '[/][.]git[/]' >> $INPUT_FILES
                    if [ $? -ne 0 ]; then
                        >&2  echo "ERROR: $FUNCNAME (${LINENO}): find '$SRC_DIR' -type f"
                        return 1
                    fi
                fi
            fi

            if [ "x$COPY_LIST_TO_TAR" != "x" ]; then
                find $(readlink -f "$COPY_LIST_TO_TAR") -type f >> $INPUT_FILES
                if [ $? -ne 0 ]; then
                    >&2  echo "ERROR: $FUNCNAME (${LINENO}): find '$COPY_LIST_TO_TAR' -type f"
                    return 1
                fi
            fi
        fi

        if [ "x$OPT_DEP_LIST" != "x" ]; then
            find $(readlink -f "$OPT_DEP_LIST") -type f >> $INPUT_FILES 2> /dev/null
            if [ $? -ne 0 ]; then
                >&2  echo "ERROR: $FUNCNAME (${LINENO}): find '$OPT_DEP_LIST' -type f"
                return 1
            fi
        fi
    )
    if [ $? -eq 1 ]; then
        return 1
    fi

    # Create sorted, unique list of cononical paths
    (
        # Regular files, get canonical path
        cat $INPUT_FILES | xargs readlink -f

        # A Symlink that likely points outside of $MY_REPO.
        # get canonical path to the symlink itself, and not
        # to what the symlink points to.
        if [ -f $INPUT_LINKS ]; then
            while IFS= read -r f; do
                echo "$(readlink -f $(dirname $f))/$(basename $f)"
            done < "$INPUT_LINKS"
        fi
    ) | sort --unique > $INPUT_FILES_SORTED

    # Remove $MY_REPO prefix from paths
    cat $INPUT_FILES_SORTED | xargs md5sum | sed "s# $(readlink -f $MY_REPO)/# #"

    if [ $TMP_FLAG -eq 0 ]; then
        \rm -f $INPUT_FILES_SORTED
        \rm -f $INPUT_FILES
        if [ -f $INPUT_LINKS ]; then
            \rm -f $INPUT_LINKS
        fi
    else
        \rm -rf $WORK_DIR
    fi

    return 0
}
