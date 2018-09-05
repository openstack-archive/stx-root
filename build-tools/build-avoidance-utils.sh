#
# Copyright (c) 2018 Wind River Systems, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

#
# Functions related to build avoidance.
#
# Do not call directly.  Used by build-pkgs.
#
# Build avoidance downloads rpm, src.rpm and other artifacts of
# build-pkgs for a local reference build.  The reference would
# typically be an automated build run atleast daily.
# The MY_WORKSPACE directory for the reference build shall have
# a common root directory, and a leaf directory that is a time stamp
# of format YYYY-MM-DD_hh-mm-ss.
#  e.g. /localdisk/loadbuild/jenkins/StarlingX/2018-07-19_11-30-21
#
# Note: Must be able to rsync and ssh to the machine that holds the
# reference builds.

BUILD_AVOIDANCE_USR=""
BUILD_AVOIDANCE_HOST=""
BUILD_AVOIDANCE_DIR=""
BUILD_AVOIDANCE_URL=""
BUILD_AVOIDANCE_DATA_DIR="$MY_WORKSPACE/build_avoidance_data"
BUILD_AVOIDANCE_SOURCE="$MY_REPO/build-data/build_avoidance_source"
BUILD_AVOIDANCE_LOCAL_SOURCE="$MY_REPO/local-build-data/build_avoidance_source"
BUILD_AVOIDANCE_TEST_CONTEXT="$BUILD_AVOIDANCE_DATA_DIR/test_context"
BUILD_AVOIDANCE_LAST_SYNC_FILE="$BUILD_AVOIDANCE_DATA_DIR/last_sync_context"

if [ ! -f $BUILD_AVOIDANCE_SOURCE ]; then
    echo "Couldn't read $BUILD_AVOIDANCE_SOURCE"
    exit 1
fi

echo "Reading: $BUILD_AVOIDANCE_SOURCE"
source $BUILD_AVOIDANCE_SOURCE

if [ -f $BUILD_AVOIDANCE_LOCAL_SOURCE ]; then
    echo "Reading: $BUILD_AVOIDANCE_LOCAL_SOURCE"
    source $BUILD_AVOIDANCE_LOCAL_SOURCE
fi



if [ "x$BUILD_AVOIDANCE_OVERRIDE_DIR" != "x" ]; then
    BUILD_AVOIDANCE_DIR="$BUILD_AVOIDANCE_OVERRIDE_DIR"
fi

if [ "x$BUILD_AVOIDANCE_OVERRIDE_HOST" != "x" ]; then
    BUILD_AVOIDANCE_HOST="$BUILD_AVOIDANCE_OVERRIDE_HOST"
fi

if [ "x$BUILD_AVOIDANCE_OVERRIDE_USR" != "x" ]; then
    BUILD_AVOIDANCE_USR="$BUILD_AVOIDANCE_OVERRIDE_USR"
fi

echo "BUILD_AVOIDANCE_DIR=$BUILD_AVOIDANCE_DIR"
echo "BUILD_AVOIDANCE_HOST=$BUILD_AVOIDANCE_HOST"
echo "BUILD_AVOIDANCE_USR=$BUILD_AVOIDANCE_USR"

build_avoidance_clean () {
    if [ -f $BUILD_AVOIDANCE_LAST_SYNC_FILE ]; then
        \rm -f -v "$BUILD_AVOIDANCE_LAST_SYNC_FILE"
    fi
}


#
# test_build_avoidance_context <path-to-context-file>
#
# Is the provided context file compatible with the current
# state of all of our gits?  A compatible context is one
# where every commit in the context file is visible in our
# current git history.
#
# Returns: Timestamp of context tested.
# Exit code: 0 = Compatible
#            1 = This context is older than the last applied
#                build avoidance context.  If you are searching
#                newest to oldest, you might as well stop.
#            2 = Not compatible
#
test_build_avoidance_context () {
    local context="$1"
    local BA_LAST_SYNC_CONTEXT="$2"
    local BA_CONTEXT=""

    BA_CONTEXT=$(basename $context | cut -d '.' -f 1)
    >&2 echo "test: $BA_CONTEXT"

    if [ "$BA_CONTEXT" == "$BA_LAST_SYNC_CONTEXT" ]; then
        # Stop the search.  We've reached the last sync point
        BA_CONTEXT=""
        echo "$BA_CONTEXT"
        return 1
    fi

    git_test_context "$context"
    result=$?
    if [ $result -eq 0 ]; then
        # found a new context !!!
        echo "$BA_CONTEXT"
        return 0
    fi

    # Continue the search
    BA_CONTEXT=""
    echo "$BA_CONTEXT"
    return 2
}


#
# get_build_avoidance_context
#
# Return URL of the most recent jenkins build that is compatable with
# the current software context under $MY_REPO.
#
get_build_avoidance_context () {
    (
    local context
    local BA_CONTEXT=""
    local BA_LAST_SYNC_CONTEXT=""

    # Load last synced context
    if [ -f $BUILD_AVOIDANCE_LAST_SYNC_FILE ]; then
        BA_LAST_SYNC_CONTEXT=$(head -n 1 $BUILD_AVOIDANCE_LAST_SYNC_FILE)
    fi

    mkdir -p $BUILD_AVOIDANCE_DATA_DIR
    if [ $? -ne 0 ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): mkdir -p $BUILD_AVOIDANCE_DATA_DIR"
        return 1
    fi

    local REMOTE_CTX_DIR="$BUILD_AVOIDANCE_DIR/context"
    local LOCAL_CTX_DIR="$BUILD_AVOIDANCE_DATA_DIR/context"

    # First copy the directory containing all the context files for
    # the reference builds.
    >&2 echo "Download latest reference build contexts"
    >&2 echo "rsync -avu $BUILD_AVOIDANCE_HOST:$REMOTE_CTX_DIR $BUILD_AVOIDANCE_DATA_DIR"
    rsync -avu $BUILD_AVOIDANCE_HOST:$REMOTE_CTX_DIR $BUILD_AVOIDANCE_DATA_DIR >> /dev/null
    if [ $? -ne 0 ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): rsync -avu $BUILD_AVOIDANCE_HOST:$REMOTE_CTX_DIR $BUILD_AVOIDANCE_DATA_DIR"
        return 1
    fi

    # Search for a new context to sync
    cd $MY_REPO

    if [ "$BUILD_AVOIDANCE_DAY" == "" ]; then
        # Normal case:
        # Search all contexts, newest to oldest, for a good context.
        for context in $(ls -1rd $LOCAL_CTX_DIR/*context); do
            >&2 echo "context=$context"
            BA_CONTEXT=$(test_build_avoidance_context $context $BA_LAST_SYNC_CONTEXT)
            if [ $? -le 1 ]; then
                # Stop search.  Might or might not have found a good context.
                break;
            fi
        done
    else
        # Special case when a target day is specified.  Why would we do this?
        # Reason is we might want the reference build to itself use build
        # avoidance referencing prior builds of itself, except for one build
        # a week when we use a full build rather than a build avoidance build.
        #    e.g.   Sunday - full build
        #           Mon-Sat - avoidance builds that refernce Sunday build.
        #
        # Starting from last <TARG_DAY> (e.g. "Sunday"), search newest to 
        # oldest for a good context.  If none found, increment the traget 
        # day (e.g. Monday) and search again.  Keep incrementing until a 
        # good build is found, or the offset target day enters the furure.
        #
        local TARG_DAY=$BUILD_AVOIDANCE_DAY
        local TODAY_DATE
        local TODAY_DAY
        local TARG_DATE=""
        local TARG_TS
        local TODAY_TS

        TODAY_DATE=$(date  +%Y-%m-%d)
        TODAY_DAY=$(date "+%A")

        for OFFSET_DAYS in 0 1 2 3 4 5 6; do
            if [ "$TARG_DAY" != "" ]; then
                # Convert TARG_DAY+OFFSET_DAYS to TARG_DATE

                if [ "$TODAY_DAY" == "$TARG_DAY" ]; then
                    TARG_DATE=$(date -d"$TARG_DAY+$OFFSET_DAYS days" +%Y-%m-%d)
                else
                    TARG_DATE=$(date -d"last-$TARG_DAY+$OFFSET_DAYS days" +%Y-%m-%d)
                fi
                >&2 echo "TARG_DATE=$TARG_DATE"

                TARG_TS=$(date -d "$TARG_DATE" +%s)
                TODAY_TS=$(date -d "$TODAY_DATE" +%s)
                if [ $TARG_TS -gt $TODAY_TS ]; then
                    # Skip if offset has pushed us into future dates
                    continue;
                fi

                if [ "$TARG_DATE" == "$TODAY_DATE" ]; then
                    TARG_DATE=""
                fi
            fi

            # Search build, newest to oldest, satisfying TARG_DATE
            for f in $(ls -1rd $LOCAL_CTX_DIR/*context); do
                DATE=$(echo $(basename "$f") | cut -d '_' -f 1)
                >&2 echo "   DATE=$DATE, TARG_DATE=$TARG_DATE"

                if [ "$DATE" == "$TARG_DATE" ] || [ "$TARG_DATE" == "" ] ; then
                    context=$f;
                else
                    continue
                fi

                >&2 echo "context=$context"

                BA_CONTEXT=$(test_build_avoidance_context $context $BA_LAST_SYNC_CONTEXT)

                if [ $? -le 1 ]; then
                    # Stop search.  Might or might not have found a good context.
                    break;
                fi
            done

            if [ "$BA_CONTEXT" != "" ]; then
                # Found a good context.
                break
            fi
        done
    fi

    if [ "$BA_CONTEXT" == "" ]; then
        # No new context found
        return 1
    fi

    # test that the reference build context hasn't been deleted
    local BA_CONTEXT_DIR="$BUILD_AVOIDANCE_DIR/$BA_CONTEXT"
    >&2 echo "ssh $BUILD_AVOIDANCE_HOST '[ -d $BA_CONTEXT_DIR ]'"
    if ! ssh $BUILD_AVOIDANCE_HOST '[ -d $BA_CONTEXT_DIR ]' ; then
        return 1
    fi

    # Save the latest context
    >&2 echo "BA_CONTEXT=$BA_CONTEXT"
    >&2 echo "BUILD_AVOIDANCE_LAST_SYNC_FILE=$BUILD_AVOIDANCE_LAST_SYNC_FILE"
    echo $BA_CONTEXT > $BUILD_AVOIDANCE_LAST_SYNC_FILE

    # The location of the load with the most compatable new context
    URL=$BUILD_AVOIDANCE_HOST:$BA_CONTEXT_DIR

    # return URL to caller.  
    echo $URL
    return 0
    )
}


#
# build_avoidance_pre_clean <build-type>
#
# A place for any cleanup actions that must preceed a build avoidance build.
#
build_avoidance_pre_clean () {
    local BUILD_TYPE="$1"

    if [ "$BUILD_TYPE" == "" ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): BUILD_TYPE required"
        return 1
    fi

    # clean prior builds
    if [ -d $MY_WORKSPACE/$BUILD_TYPE ]; then
        build-pkgs --clean --$BUILD_TYPE --no-build-avoidance
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    for f in $BUILD_AVOIDANCE_SRPM_FILES $BUILD_AVOIDANCE_RPM_FILES; do
        if [ -f $MY_WORKSPACE/$BUILD_TYPE/$f ]; then
            \rm -f $MY_WORKSPACE/$BUILD_TYPE/$f
            if [ $? -ne 0 ]; then
                >&2 echo "Error: $FUNCNAME (${LINENO}): rm -f $MY_WORKSPACE/$BUILD_TYPE/$f"
                return 1
            fi
        fi
    done

    for d in $BUILD_AVOIDANCE_SRPM_DIRECTORIES $BUILD_AVOIDANCE_RPM_DIRECTORIES; do

        if [ -d $MY_WORKSPACE/$BUILD_TYPE/$d ]; then
            \rm -rf $MY_WORKSPACE/$BUILD_TYPE/$d
            if [ $? -ne 0 ]; then
                >&2 echo "Error: $FUNCNAME (${LINENO}): rm -rf $MY_WORKSPACE/$BUILD_TYPE/$d"
                return 1
            fi
        fi
    done

    return 0
}


#
# build_avoidance_rsync <build-type>
#
# Copy the needed build artifacts for <build-type> from $BUILD_AVOIDANCE_URL.
#
build_avoidance_rsync () {
    local BUILD_TYPE="$1"

    if [ "$BUILD_TYPE" == "" ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): BUILD_TYPE required"
        return 1
    fi

    for d in $BUILD_AVOIDANCE_SRPM_DIRECTORIES $BUILD_AVOIDANCE_RPM_DIRECTORIES; do

        mkdir -p $MY_WORKSPACE/$BUILD_TYPE/$d
        if [ $? -ne 0 ]; then
            >&2 echo "Error: $FUNCNAME (${LINENO}): mkdir -p $MY_WORKSPACE/$BUILD_TYPE/$d"
            return 1
        fi

        echo "rsync -avu $BUILD_AVOIDANCE_URL/$BUILD_TYPE/$d/* $MY_WORKSPACE/$BUILD_TYPE/$d/"
        rsync -avu $BUILD_AVOIDANCE_URL/$BUILD_TYPE/$d/* $MY_WORKSPACE/$BUILD_TYPE/$d/
        if [ $? -ne 0 ]; then
            >&2 echo "Error: $FUNCNAME (${LINENO}): rsync -avu $BUILD_AVOIDANCE_URL/$BUILD_TYPE/$d/* $MY_WORKSPACE/$BUILD_TYPE/$d/"
            return 1
        fi
    done

    for f in $BUILD_AVOIDANCE_SRPM_FILES $BUILD_AVOIDANCE_RPM_FILES; do
        mkdir -p $MY_WORKSPACE/$BUILD_TYPE/$(dirname $f)
        if [ $? -ne 0 ]; then
            >&2 echo "Error: $FUNCNAME (${LINENO}): mkdir -p $MY_WORKSPACE/$BUILD_TYPE/$(dirname $f)"
            return 1
        fi

        echo "rsync -avu $BUILD_AVOIDANCE_URL/$BUILD_TYPE/$f $MY_WORKSPACE/$BUILD_TYPE/$(dirname $f)"
        rsync -avu $BUILD_AVOIDANCE_URL/$BUILD_TYPE/$f $MY_WORKSPACE/$BUILD_TYPE/$(dirname $f)/
        if [ $? -ne 0 ]; then
            >&2 echo "Error: $FUNCNAME (${LINENO}): rsync -avu $BUILD_AVOIDANCE_URL/$BUILD_TYPE/$f $MY_WORKSPACE/$BUILD_TYPE/$(dirname $f)/"
            return 1
        fi
    done

    return 0
}

#
# build_avoidance_fixups <build-type>
#
# Fix paths in the build artifacts that we coppied that contain
# the user name.
#
# Also, our credentials may differ from the reference build,
# so substitute unsigned packages in place of signed packages.
#
build_avoidance_fixups () {
    local BUILD_TYPE="$1"

    local BA_SOURCE_BUILD_ENVIRONMENT
    BA_SOURCE_BUILD_ENVIRONMENT="${BUILD_AVOIDANCE_USR}-$(basename $(dirname $BUILD_AVOIDANCE_URL))-$(basename $BUILD_AVOIDANCE_URL)-${SRC_BUILD_ENVIRONMENT}"
    local RESULT_DIR=""
    local FROM_DIR=""
    local TO_DIR=""
    local r
    local r2
    local b
    local m
    local m2

    if [ "$BUILD_TYPE" == "" ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): BUILD_TYPE required"
        return 1
    fi

    RESULT_DIR="$MY_WORKSPACE/$BUILD_TYPE/results"
    FROM_DIR="${RESULT_DIR}/${BA_SOURCE_BUILD_ENVIRONMENT}-${BUILD_TYPE}"
    TO_DIR="${RESULT_DIR}/${MY_BUILD_ENVIRONMENT}-${BUILD_TYPE}"
    echo "$FUNCNAME: FROM_DIR=$FROM_DIR"
    echo "$FUNCNAME: TO_DIR=$TO_DIR"
    echo "$FUNCNAME: MY_BUILD_ENVIRONMENT=$MY_BUILD_ENVIRONMENT"

    # Fix patchs the use MY_BUILD_ENVIRONMENT
    if [ ! -d "$FROM_DIR" ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): Expected directory '$FROM_DIR' is missing."
        return 1
    fi

    echo "$FUNCNAME: mv '$FROM_DIR' '$TO_DIR'"
    \mv "$FROM_DIR" "$TO_DIR"
    if [ $? -ne 0 ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): mv '$FROM_DIR' '$TO_DIR'"
        return 1
    fi

    local MY_WS_BT="$MY_WORKSPACE/$BUILD_TYPE"

    # Replace signed rpms with non-signed copies .... we aren't a formal build
    for r in $(find $MY_WS_BT/rpmbuild/RPMS -type f -name '*.rpm' | grep -v src.rpm); do

        b=$(basename $r)
        r2=$(find $MY_WS_BT/results -name $b | head -n1)
        if [ "$r2" != "" ]; then
            m=$(md5sum ${r} | cut -d ' ' -f 1)
            m2=$(md5sum ${r2} | cut -d ' ' -f 1)
            if [ "${m}" != "${m2}" ]; then
                echo "$FUNCNAME: fixing $b"
                \rm -f ${r}
                if [ $? -ne 0 ]; then
                    >&2 echo "Error: $FUNCNAME (${LINENO}): rm -f ${r}"
                    return 1
                fi

                \cp ${r2} ${r}
                if [ $? -ne 0 ]; then
                    >&2 echo "Error: $FUNCNAME (${LINENO}): cp ${r2} ${r}"
                    return 1
                fi
            fi
        fi;
    done

    return 0
}


#
# build_avoidance <build-type>
#
# Look for a reference build that is applicable to our current git context.
# and copy it to our local workspace, if we haven't already done so.
#
build_avoidance () {
    local BUILD_TYPE="$1"

    echo "==== Build Avoidance Start ===="

    if [ "$BUILD_TYPE" == "" ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): BUILD_TYPE required"
        return 1
    fi

    if [ "$BUILD_TYPE" == "installer" ]; then
        >&2 echo "build_avoidance: BUILD_TYPE==installer not supported"
        return 1
    fi

    build_avoidance_pre_clean $BUILD_TYPE
    if [ $? -ne 0 ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): build_avoidance_pre_clean $BUILD_TYPE"
        return 1
    fi

    build_avoidance_rsync $BUILD_TYPE
    if [ $? -ne 0 ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): build_avoidance_rsync $BUILD_TYPE"
        return 1
    fi

    build_avoidance_fixups $BUILD_TYPE
    if [ $? -ne 0 ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): build_avoidance_fixups $BUILD_TYPE"
        return 1
    fi

    echo "==== Build Avoidance Complete ===="
    return 0
}

#
# build_avoidance_save_reference_context
#
# For use by a reference build.  Copy the 'CONTEXT' file
# from the build into a central directory where we save
# the context of old builds.
#
# Individual reference builds use:
#     MY_WORKSPACE=<common-dir>/<timestamp>
# and context files are collected in dir:
#     DEST_CTX_DIR=<common-dir>/context
# using name:
#     DEST_CTX=<timestamp>.context

build_avoidance_save_reference_context () {
    local DIR
    DIR=$(dirname "${MY_WORKSPACE}")

    # Note: SUB_DIR should be a timestamp
    local SUB_DIR
    SUB_DIR=$(basename "${MY_WORKSPACE}")

    local SRC_CTX="${MY_WORKSPACE}/CONTEXT"
    local DEST_CTX_DIR="${DIR}/context"
    local DEST_CTX="${DEST_CTX_DIR}/${SUB_DIR}.context"

    if [ ! -f "${SRC_CTX}" ]; then
        echo "Context file not found at '${SRC_CTX}'"
        return 1
    fi

    mkdir -p "${DEST_CTX_DIR}"
    if [ $? -ne 0 ]; then
        echo "Error: $FUNCNAME (${LINENO}): Failed to create directory '${DEST_CTX_DIR}'"
        return 1
    fi

    cp "${SRC_CTX}" "${DEST_CTX}"
    if [ $? -ne 0 ]; then
        echo "Error: $FUNCNAME (${LINENO}): Failed to copy ${SRC_CTX} -> ${DEST_CTX}"
        return 1
    fi

    return 0
}
