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
# in a sortable parsable format.   Default YYYYMMDDThhmmssZ.
#  e.g. /localdisk/loadbuild/jenkins/StarlingX/20180719T113021Z
#
# Other formats can be used by setting the following variables
# in $MY_REPO/local-build-data/build_avoidance_source.
#   e.g. to allow format YYYY-MM-DD_hh-mm-ss
# BUILD_AVOIDANCE_DATE_FORMAT="%Y-%m-%d"
# BUILD_AVOIDANCE_TIME_FORMAT="%H-%M-%S"
# BUILD_AVOIDANCE_DATE_TIME_DELIM="_"
# BUILD_AVOIDANCE_DATE_TIME_POSTFIX=""
#
# Note: Must be able to rsync and ssh to the machine that holds the
# reference builds.
#
# In future alternative transfer protocols may be supported.
# Select the alternate protocol by setting the following variables
# in $MY_REPO/local-build-data/build_avoidance_source.
# e.g.
# BUILD_AVOIDANCE_FILE_TRANSFER="my-supported-prototcol"
#

BUILD_AVOIDANCE_USR=""
BUILD_AVOIDANCE_HOST=""
BUILD_AVOIDANCE_DIR=""
BUILD_AVOIDANCE_URL=""

# Default date/time format, iso-8601 compact, 20180912T143913Z
# Syntax is a subset of that use by the unix 'date' command.
BUILD_AVOIDANCE_DATE_FORMAT="%Y%m%d"
BUILD_AVOIDANCE_TIME_FORMAT="%H%M%S"
BUILD_AVOIDANCE_DATE_TIME_DELIM="T"
BUILD_AVOIDANCE_DATE_TIME_POSTFIX="Z"

# Default file transfer method
BUILD_AVOIDANCE_FILE_TRANSFER="rsync"

# Default is to use timestamps and days in UTC
#
# If you prefer local time, then set 'BUILD_AVOIDANCE_DATE_UTC=0'
# in '$MY_REPO/local-build-data/build_avoidance_source'
BUILD_AVOIDANCE_DATE_UTC=1

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

UTC=""

if [ $BUILD_AVOIDANCE_DATE_UTC -eq 1 ]; then
    UTC="--utc"
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


date_to_iso_8601 () {
    local DATE="$1"
    local CENTURY=""
    local YEAR_IN_CENTURY="00"
    local MONTH="01"
    local DAY="01"
    local DAY_OF_YEAR=""

    CENTURY="$(date  '+%C')"

    for x in $(echo "${BUILD_AVOIDANCE_DATE_FORMAT}" | tr ' ' '#' | sed 's/%%/#/g' | tr '%' ' ' ); do
        # Consume format case options
        case ${x:0:1} in
            ^) x=${x:1};;
            \#) x=${x:1};;
            *) ;;
        esac

        # Process format
        case $x in
            Y*)  CENTURY=${DATE:0:2}; YEAR_IN_CENTURY=${DATE:2:2}; DATE=${DATE:4}; x=${x:1};;
            0Y*) CENTURY=${DATE:0:2}; YEAR_IN_CENTURY=${DATE:2:2}; DATE=${DATE:4}; x=${x:2};;
            _Y*) CENTURY=$(echo "${DATE:0:2}" | tr ' ' '0'); YEAR_IN_CENTURY=${DATE:2:2}; DATE=${DATE:4}; x=${x:2};;

            y*)  YEAR_IN_CENTURY=${DATE:0:2}; DATE=${DATE:2}; x=${x:1};;
            0y*) YEAR_IN_CENTURY=${DATE:0:2}; DATE=${DATE:2}; x=${x:2};;
            _y*) YEAR_IN_CENTURY=$(echo "${DATE:0:2}" | tr ' ' '0'); DATE=${DATE:2}; x=${x:2};;

            C*)  CENTURY=${DATE:0:2}; DATE=${DATE:2}; x=${x:1};;
            0C*) CENTURY=${DATE:0:2}; DATE=${DATE:2}; x=${x:2};;
            _C*) CENTURY=$(echo "${DATE:0:2}" | tr ' ' '0'); DATE=${DATE:2}; x=${x:2};;

            m*)  MONTH=${DATE:0:2}; DATE=${DATE:2}; x=${x:1};;
            0m*) MONTH=${DATE:0:2}; DATE=${DATE:2}; x=${x:2};;
            _m*) MONTH=$(echo "${DATE:0:2}" | tr ' ' '0'); DATE=${DATE:2}; x=${x:2};;
            e*)  MONTH=$(echo "${DATE:0:2}" | tr ' ' '0'); DATE=${DATE:2}; x=${x:1};;
            0e*) MONTH=${DATE:0:2}; DATE=${DATE:2}; x=${x:2};;
            _e*) MONTH=$(echo "${DATE:0:2}" | tr ' ' '0'); DATE=${DATE:2}; x=${x:2};;
            b*)  MONTH="$(date -d "${DATE:0:3} 1 2000" '+%m')"; DATE=${DATE:3}; x=${x:1};;
            h*)  MONTH="$(date -d "${DATE:0:3} 1 2000" '+%m')"; DATE=${DATE:3}; x=${x:1};;

            d*)  DAY=${DATE:0:2}; DATE=${DATE:2}; x=${x:1};;
            0d*) DAY=${DATE:0:2}; DATE=${DATE:2}; x=${x:2};;
            _d*) DAY=$(echo "${DATE:0:2}" | tr ' ' '0'); DATE=${DATE:2}; x=${x:2};;

            j*)  DAY_OF_YEAR=${DATE:0:3}; DATE=${DATE:3}; x=${x:1};;
            0j*) DAY_OF_YEAR=${DATE:0:3}; DATE=${DATE:3}; x=${x:2};;
            _j*) DAY_OF_YEAR=$(echo "${DATE:0:3}" | tr ' ' '0'); DATE=${DATE:3}; x=${x:2};;

            D*) MONTH=${DATE:0:2}; DAY=${DATE:3:2}; YEAR_IN_CENTURY=${DATE:6:2}; DATE=${DATE:8}; x=${x:1};;
            F*) CENTURY=${DATE:0:2}; YEAR_IN_CENTURY=${DATE:2:2}; MONTH=${DATE:5:2}; DAY=${DATE:8:2}; DATE=${DATE:10}; x=${x:1};;
            *) >&2 echo "$FUNCNAME (${LINENO}): Unsupported date format: ${BUILD_AVOIDANCE_DATE_FORMAT}"; return 1;;
        esac

        # consume remaing non-interpreted content
        if [ "$(echo "${DATE:0:${#x}}" |  tr ' ' '#')" != "${x}" ]; then
            >&2 echo "$FUNCNAME (${LINENO}): Unexpected content '${DATE:0:${#x}}' does not match expected '${x}': '$1' being parsed vs '${BUILD_AVOIDANCE_DATE_FORMAT}'"
            return 1
        fi
        DATE=${DATE:${#x}}
    done

    if [ "${DAY_OF_YEAR}" != "" ]; then
        local YEAR_SEC
        local DOY_SEC
        YEAR_SEC="$(date -d "${CENTURY}${YEAR_IN_CENTURY}-01-01" '+%s')"
        DOY_SEC=$((YEAR_SEC+(DAY_OF_YEAR-1)*24*60*60))
        MONTH="$(date "@$DOY_SEC" "+%m")"
        DAY="$(date "@$DOY_SEC" "+%d")"
    fi

    echo "${CENTURY}${YEAR_IN_CENTURY}-${MONTH}-${DAY}"
    return 0
}

time_to_iso_8601 () {
    TIME="$1"
    local HOUR="00"
    local H12=""
    local AMPM=""
    local MINUTE="00"
    local SECOND="00"

    CENTURY="$(date  '+%C')"

    for x in $(echo "${BUILD_AVOIDANCE_TIME_FORMAT}" | tr ' ' '#' | sed 's/%%/#/g' | tr '%' ' ' ); do
        # Consume format case options
        case ${x:0:1} in
            ^) x=${x:1};;
            \#) x=${x:1};;
            *) ;;
        esac

        # Process format
        case $x in
            H*)  HOUR=${TIME:0:2}; TIME=${TIME:2}; x=${x:1};;
            0H*) HOUR=${TIME:0:2}; TIME=${TIME:2}; x=${x:2};;
            _H*) HOUR="$(echo "${TIME:0:2}" | tr ' ' '0')"; TIME=${TIME:2}; x=${x:2};;
            k*)  HOUR="$(echo "${TIME:0:2}" | tr ' ' '0')"; TIME=${TIME:2}; x=${x:1};;
            0k*) HOUR=${TIME:0:2}; TIME=${TIME:2}; x=${x:2};;
            _k*) HOUR="$(echo "${TIME:0:2}" | tr ' ' '0')"; TIME=${TIME:2}; x=${x:2};;

            I*)  H12=${TIME:0:2}; TIME=${TIME:2}; x=${x:1};;
            0I*) H12=${TIME:0:2}; TIME=${TIME:2}; x=${x:2};;
            _I*) H12="$(echo "${TIME:0:2}" | tr ' ' '0')"; TIME=${TIME:2}; x=${x:2};;
            l*)  H12="$(echo "${TIME:0:2}" | tr ' ' '0')"; TIME=${TIME:2}; x=${x:1};;
            0l*) H12=${TIME:0:2}; TIME=${TIME:2}; x=${x:2};;
            _l*) H12="$(echo "${TIME:0:2}" | tr ' ' '0')"; TIME=${TIME:2}; x=${x:2};;
            p*) AMPM=${TIME:0:2}; TIME=${TIME:2}; x=${x:1};;

            M*)  MINUTE=${TIME:0:2}; TIME=${TIME:2}; x=${x:1};;
            0M*) MINUTE=${TIME:0:2}; TIME=${TIME:2}; x=${x:2};;
            _M*) MINUTE="$(echo "${TIME:0:2}" | tr ' ' '0')"; TIME=${TIME:2}; x=${x:2};;

            S*)  SECOND=${TIME:0:2}; TIME=${TIME:2}; x=${x:1};;
            0S*) SECOND=${TIME:0:2}; TIME=${TIME:2}; x=${x:2};;
            _S*) SECOND="$(echo "${TIME:0:2}" | tr ' ' '0')"; TIME=${TIME:2}; x=${x:2};;

            R*) HOUR=${TIME:0:2}; MINUTE=${TIME:3:2} TIME=${TIME:5}; x=${x:1};;
            r*) H12=${TIME:0:2}; MINUTE=${TIME:3:2}; SECOND=${TIME:6:2}; AMPM=${TIME:9:2}; TIME=${TIME:11}; x=${x:1};;
            T*) HOUR=${TIME:0:2}; MINUTE=${TIME:3:2}; SECOND=${TIME:6:2}; TIME=${TIME:8}; x=${x:1};;

            *) >&2 echo "$FUNCNAME (${LINENO}): Unsupported time format: ${BUILD_AVOIDANCE_TIME_FORMAT}"; return 1;;
        esac

        # consume remaing non-interpreted content
        if [ "$(echo "${TIME:0:${#x}}" |  tr ' ' '#')" != "${x}" ]; then
            >&2 echo "$FUNCNAME (${LINENO}): Unexpected content '${TIME:0:${#x}}' does not match expected '${x}': '$1' being parsed vs '${BUILD_AVOIDANCE_TIME_FORMAT}'"
            return 1
        fi
        TIME=${TIME:${#x}}
    done

    if [ "$H12" != "" ] && [ "$AMPM" != "" ]; then
        HOUR="$(date "$H12:01:01 $AMPM" '+%H')"
    else
        if [ "$H12" != "" ] && [ "$AMPM" != "" ]; then
            >&2 echo "$FUNCNAME (${LINENO}): Unsupported time format: ${BUILD_AVOIDANCE_TIME_FORMAT}"
            return 1
        fi
    fi

    echo "${HOUR}:${MINUTE}:${SECOND}"
    return 0
}

date_time_to_iso_8601 () {
    local DATE_TIME="$1"
    local DATE
    local TIME
    local DECODED_DATE
    local DECODED_TIME
    DATE=$(echo "${DATE_TIME}" | cut -d ${BUILD_AVOIDANCE_DATE_TIME_DELIM} -f 1)
    TIME=$(echo "${DATE_TIME}" | cut -d ${BUILD_AVOIDANCE_DATE_TIME_DELIM} -f 2 | sed "s#${BUILD_AVOIDANCE_DATE_TIME_POSTFIX}\$##")
    DECODED_DATE=$(date_to_iso_8601 "${DATE}")
    DECODED_TIME=$(time_to_iso_8601 "${TIME}")
    echo "${DECODED_DATE}T${DECODED_TIME}$(date $UTC '+%:z')"
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

    local REMOTE_CTX_DIR="context"
    local LOCAL_CTX_DIR="$BUILD_AVOIDANCE_DATA_DIR/context"

    # First copy the directory containing all the context files for
    # the reference builds.
    >&2 echo "Download latest reference build contexts"

    # Must set this prior to build_avoidance_copy_dir.
    # The setting is not exported outside of the subshell.
    BUILD_AVOIDANCE_URL="$BUILD_AVOIDANCE_HOST:$BUILD_AVOIDANCE_DIR"

    build_avoidance_copy_dir "$REMOTE_CTX_DIR" "$LOCAL_CTX_DIR"
    if [ $? -ne 0 ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): build_avoidance_copy_dir '$REMOTE_CTX_DIR' '$LOCAL_CTX_DIR'"
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
        # oldest for a good context.  If none found, increment the target
        # day (e.g. Monday) and search again.  Keep incrementing until a
        # good build is found, or target day + offset days would be a date
        # in the furure.
        #
        local TARG_DAY=$BUILD_AVOIDANCE_DAY
        local TODAY_DATE
        local TODAY_DAY
        local TARG_DATE=""
        local TARG_TS
        local TODAY_TS

        TODAY_DATE=$(date  $UTC +%Y-%m-%d)
        TODAY_DAY=$(date $UTC "+%A")

        for OFFSET_DAYS in 0 1 2 3 4 5 6; do
            if [ "$TARG_DAY" != "" ]; then
                # Convert TARG_DAY+OFFSET_DAYS to TARG_DATE

                if [ "$TODAY_DAY" == "$TARG_DAY" ]; then
                    TARG_DATE=$(date $UTC -d"$TARG_DAY+$OFFSET_DAYS days" +%Y-%m-%d)
                else
                    TARG_DATE=$(date $UTC -d"last-$TARG_DAY+$OFFSET_DAYS days" +%Y-%m-%d)
                fi
                >&2 echo "TARG_DATE=$TARG_DATE"

                TARG_TS=$(date $UTC -d "$TARG_DATE" +%s)
                TODAY_TS=$(date $UTC -d "$TODAY_DATE" +%s)
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
                DATE=$(date_to_iso_8601 $(basename "$f"))
                if [ $? -ne 0 ]; then
                    >&2 echo "Failed to extract date from filename '$(basename "$f")', ignoring file"
                    continue
                fi

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
# build_avoidance_copy_dir_rsync <remote-dir-path-rel> <local-dir-path> ['verbose']
#
# Copy a file from $BUILD_AVOIDANCE_URL/<remote-dir-path-rel>
# to <local-dir-path> using rsync.
#
build_avoidance_copy_dir_rsync () {
    local FROM="$1"
    local TO="$2"
    local VERBOSE="$3"
    local FLAGS="-a -u"

    if [ "$BUILD_AVOIDANCE_URL" == "" ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): BUILD_AVOIDANCE_URL no set"
        return 1
    fi
    if [ "$VERBOSE" != "" ]; then
        FLAGS="$FLAGS -v"
        echo "rsync $FLAGS '$BUILD_AVOIDANCE_URL/$FROM/*' '$TO/'"
    fi
    rsync $FLAGS "$BUILD_AVOIDANCE_URL/$FROM/*" "$TO/"
    return $?
}

#
# build_avoidance_copy_file_rsync <remote-file-path-rel> <local-file-path> ['verbose']
#
# Copy a file from $BUILD_AVOIDANCE_URL/<remote-file-path-rel>
# to <local-file-path> using rsync.
#
build_avoidance_copy_file_rsync () {
    local FROM="$1"
    local TO="$2"
    local VERBOSE="$3"
    local FLAGS="-a -u"

    if [ "$BUILD_AVOIDANCE_URL" == "" ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): BUILD_AVOIDANCE_URL no set"
        return 1
    fi
    if [ "$VERBOSE" != "" ]; then
        FLAGS="$FLAGS -v"
        echo "rsync $FLAGS '$BUILD_AVOIDANCE_URL/$FROM' '$TO'"
    fi
    rsync $FLAGS "$BUILD_AVOIDANCE_URL/$FROM" "$TO"
    return $?
}

#
# build_avoidance_copy_dir <remote-dir-path-rel> <local-dir-path> ['verbose']
#
# Copy a file from $BUILD_AVOIDANCE_URL/<remote-dir-path-rel>
# to <local-dir-path>.  The copy method will be determined by
# BUILD_AVOIDANCE_FILE_TRANSFER.  Only 'rsync' is supported at present.
#
# <local-dir-path> should be a directory,
# mkdir -p will be called on <local-file-path>.
#
build_avoidance_copy_dir () {
    local FROM="$1"
    local TO="$2"
    local VERBOSE="$3"

    if [ "$VERBOSE" != "" ]; then
        echo "mkdir -p '$TO'"
    fi
    mkdir -p "$TO"
    if [ $? -ne 0 ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): mkdir -p $TO"
        return 1
    fi

    case ${BUILD_AVOIDANCE_FILE_TRANSFER} in
        rsync)
            build_avoidance_copy_dir_rsync "$FROM" "$TO" "$VERBOSE"
            return $?
            ;;
        *)
            >&2 echo "Error: $FUNCNAME (${LINENO}): Unknown BUILD_AVOIDANCE_FILE_TRANSFER '${BUILD_AVOIDANCE_FILE_TRANSFER}'"
            return 1
            ;;
    esac
    return 1
}

#
# build_avoidance_copy_file <remote-file-path-rel> <local-file-path> ['verbose']
#
# Copy a file from $BUILD_AVOIDANCE_URL/<remote-file-path-rel>
# to <local-file-path>.  The copy method will be determined by
# BUILD_AVOIDANCE_FILE_TRANSFER.  Only 'rsync' is supported at present.
#
# <local-file-path> should be a file, not a directory,
# mkdir -p will be called on $(dirname <local-file-path>)
#
build_avoidance_copy_file () {
    local FROM="$1"
    local TO="$2"
    local VERBOSE="$3"

    if [ "$VERBOSE" != "" ]; then
        echo "mkdir -p $(dirname '$TO')"
    fi
    mkdir -p "$(dirname "$TO")"
    if [ $? -ne 0 ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): mkdir -p $(dirname "$TO")"
        return 1
    fi

    case ${BUILD_AVOIDANCE_FILE_TRANSFER} in
        rsync)
            build_avoidance_copy_file_rsync "$FROM" "$TO" "$VERBOSE"
            return $?
            ;;
        *)
            >&2 echo "Error: $FUNCNAME (${LINENO}): Unknown BUILD_AVOIDANCE_FILE_TRANSFER '${BUILD_AVOIDANCE_FILE_TRANSFER}'"
            return 1
            ;;
    esac
    return 1
}

#
# build_avoidance_copy <build-type> ['verbose']
#
# Copy the needed build artifacts for <build-type> from $BUILD_AVOIDANCE_URL.
#
build_avoidance_copy () {
    local BUILD_TYPE="$1"
    local VERBOSE="$2"

    if [ "$BUILD_TYPE" == "" ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): BUILD_TYPE required"
        return 1
    fi

    # Iterate through list of directories to copy
    for d in $BUILD_AVOIDANCE_SRPM_DIRECTORIES $BUILD_AVOIDANCE_RPM_DIRECTORIES; do
        build_avoidance_copy_dir "$BUILD_TYPE/$d" "$MY_WORKSPACE/$BUILD_TYPE/$d" "$VERBOSE"
        if [ $? -ne 0 ]; then
            >&2 echo "Error: $FUNCNAME (${LINENO}): build_avoidance_copy_dir '$BUILD_TYPE/$d' '$MY_WORKSPACE/$BUILD_TYPE/$d'"
            return 1
        fi
    done

    # Iterate through list of files to copy
    for f in $BUILD_AVOIDANCE_SRPM_FILES $BUILD_AVOIDANCE_RPM_FILES; do
        build_avoidance_copy_file "$BUILD_TYPE/$f" "$MY_WORKSPACE/$BUILD_TYPE/$f" "$VERBOSE"
        if [ $? -ne 0 ]; then
            >&2 echo "Error: $FUNCNAME (${LINENO}): build_avoidance_copy_file '$BUILD_TYPE/$f' '$MY_WORKSPACE/$BUILD_TYPE/$f'"
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
    local rpm_path_post_signing
    local rpm_path_pre_signing
    local rpm_name
    local md5sum_post_signing
    local md5sum_pre_signing

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
    for rpm_path_post_signing in $(find $MY_WS_BT/rpmbuild/RPMS -type f -name '*.rpm' | grep -v src.rpm); do

        rpm_name=$(basename $rpm_path_post_signing)
        rpm_path_pre_signing=$(find $MY_WS_BT/results -name $b | head -n1)
        if [ "$rpm_path_pre_signing" != "" ]; then
            md5sum_post_signing=$(md5sum ${rpm_path_post_signing} | cut -d ' ' -f 1)
            md5sum_pre_signing=$(md5sum ${rpm_path_pre_signing} | cut -d ' ' -f 1)
            if [ "${md5sum_post_signing}" != "${md5sum_pre_signing}" ]; then
                echo "$FUNCNAME: fixing $rpm_name"
                \rm -f ${rpm_path_post_signing}
                if [ $? -ne 0 ]; then
                    >&2 echo "Error: $FUNCNAME (${LINENO}): rm -f ${rpm_path_post_signing}"
                    return 1
                fi

                \cp ${rpm_path_pre_signing} ${rpm_path_post_signing}
                if [ $? -ne 0 ]; then
                    >&2 echo "Error: $FUNCNAME (${LINENO}): cp ${rpm_path_pre_signing} ${rpm_path_post_signing}"
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

    build_avoidance_copy $BUILD_TYPE 'verbose'
    if [ $? -ne 0 ]; then
        >&2 echo "Error: $FUNCNAME (${LINENO}): build_avoidance_copy $BUILD_TYPE"
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
