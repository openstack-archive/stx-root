#!/bin/env bash
function generate_dep_list {
    TMP_RPM_DB=$(mktemp -d $(pwd)/tmp_rpm_db_XXXXXX)
    mkdir -p $TMP_RPM_DB
    rpm --initdb --dbpath $TMP_RPM_DB
    rpm --dbpath $TMP_RPM_DB --test -Uvh --replacefiles '*.rpm' >> $DEPDETAILLISTFILE 2>&1
    rpm --dbpath $TMP_RPM_DB --test -Uvh --replacefiles '*.rpm' 2>&1 \
        | grep -v "error:" \
        | grep -v "warning:" \
        | grep -v "Preparing..." \
        | sed "s/ is needed by.*$//" | sed "s/ >=.*$//" | sort -u > $DEPLISTFILE
    rm -rf $TMP_RPM_DB
}

function install_deps {
    local DEP_LIST=""
    local DEP_LIST_FILE="$1"

    rm -f $TMPFILE

    while read DEP
    do
        DEP_LIST="${DEP_LIST} ${DEP}"
    done < $DEP_LIST_FILE

    echo "Debug: List of deps to resolve: ${DEP_LIST}"

    if [ -z "${DEP_LIST}" ]; then
        return 0
    fi

    # go through each repo and convert deps to packages

    for REPOID in `grep  '^[[].*[]]$' $YUM | grep -v '[[]main[]]' | awk -F '[][]' '{print $2 }'`; do
        echo "TMPDIR=$TMP_DIR repoquery -c $YUM --repoid=$REPOID --arch=x86_64,noarch --whatprovides ${DEP_LIST} --qf='%{name}'"
        TMPDIR=$TMP_DIR repoquery -c $YUM --repoid=$REPOID --arch=x86_64,noarch --qf='%{name}' --whatprovides ${DEP_LIST} | sed "s/kernel-debug/kernel/g" >> $TMPFILE
                \rm -rf $TMP_DIR/yum-$USER-*
    done
    sort $TMPFILE -u > $TMPFILE1
    rm $TMPFILE

    DEP_LIST=""
    while read DEP
    do
        DEP_LIST="${DEP_LIST} ${DEP}"
    done < $TMPFILE1
    rm $TMPFILE1

    # next go through each repo and install packages
    local TARGETS=${DEP_LIST}
    echo "Debug: Resolved list of deps to install: ${TARGETS}"
    local UNRESOLVED
    for REPOID in `grep  '^[[].*[]]$' $YUM | grep -v '[[]main[]]' | awk -F '[][]' '{print $2 }'`; do
        UNRESOLVED=" $TARGETS "

        if [[ ! -z "${TARGETS// }" ]]; then
            REPO_PATH=$(cat $YUM | sed -n "/^\[$REPOID\]\$/,\$p" | grep '^baseurl=' | head -n 1 | awk -F 'file://' '{print $2}' | sed 's:/$::')
            >&2  echo "TMPDIR=$TMP_DIR repoquery -c $YUM --repoid=$REPOID --arch=x86_64,noarch --resolve $TARGETS --qf='%{name} %{name}-%{version}-%{release}.%{arch}.rpm %{relativepath}'"
            TMPDIR=$TMP_DIR repoquery -c $YUM --repoid=$REPOID --arch=x86_64,noarch --resolve $TARGETS --qf="%{name} %{name}-%{version}-%{release}.%{arch}.rpm %{relativepath}" | sort -r -V >> $TMPFILE
                        \rm -rf $TMP_DIR/yum-$USER-*

            while read STR
            do
                >&2 echo "STR=$STR"
                if [ "x$STR" == "x" ]; then
                    continue
                fi

                PKG=`echo $STR | cut -d " " -f 1`
                PKG_FILE=`echo $STR | cut -d " " -f 2`
                PKG_REL_PATH=`echo $STR | cut -d " " -f 3`
                PKG_PATH="${REPO_PATH}/${PKG_REL_PATH}"

                >&2 echo "Installing PKG=$PKG PKG_FILE=$PKG_FILE PKG_REL_PATH=$PKG_REL_PATH PKG_PATH=$PKG_PATH from repo $REPOID"
                cp $PKG_PATH .
                if [ $? -ne 0 ]; then
                    >&2 echo "  Here's what I have to work with..."
                    >&2 echo "  TMPDIR=$TMP_DIR repoquery -c $YUM --repoid=$REPOID --arch=x86_64,noarch --resolve $PKG --qf=\"%{name} %{name}-%{version}-%{release}.%{arch}.rpm %{relativepath}\""
                    >&2 echo "  PKG=$PKG PKG_FILE=$PKG_FILE REPO_PATH=$REPO_PATH PKG_REL_PATH=$PKG_REL_PATH PKG_PATH=$PKG_PATH"
                fi

                echo $UNRESOLVED | grep $PKG
                echo $UNRESOLVED | grep $PKG >> /dev/null
                if [ $? -eq 0 ]; then
                    echo "$PKG found in $REPOID as $PKG" >> $BUILT_REPORT
                    echo "$PKG_PATH" >> $BUILT_REPORT
                    UNRESOLVED=$(echo "$UNRESOLVED" | sed "s# $PKG # #g")
                else
                    echo "$PKG satisfies unknown target in $REPOID" >> $BUILT_REPORT
                    echo "  but it doesn't match targets, $UNRESOLVED" >> $BUILT_REPORT
                    echo "  path $PKG_PATH" >> $BUILT_REPORT
                    FOUND_UNKNOWN=1
                fi
            done < $TMPFILE #<<< "$(TMPDIR=$TMP_DIR repoquery -c $YUM --repoid=$REPOID --arch=x86_64,noarch --resolve $TARGETS --qf=\"%{name} %{name}-%{version}-%{release}.%{arch}.rpm %{relativepath}\" | sort -r -V)"
                        \rm -rf $TMP_DIR/yum-$USER-*
            TARGETS="$UNRESOLVED"
        fi
    done
    >&2 echo "Debug: Packages still unresolved: $UNRESOLVED"
    echo "Debug: Packages still unresolved: $UNRESOLVED" >> $WARNINGS_REPORT
    echo "Debug: Packages still unresolved: $UNRESOLVED" >> $BUILT_REPORT
    >&2 echo ""
}

function check_all_explicit_deps_installed {

    PKGS_TO_CHECK=" "
    while read PKG_TO_ADD
    do
        PKGS_TO_CHECK="$PKGS_TO_CHECK ${PKG_TO_ADD}"
    done < $DEPLISTFILE
    rpm -qp ${INSTALLDIR}/*.rpm --qf="%{name}\n" > $TMPFILE

    echo "checking... $PKGS_TO_CHECK vs ${INSTALLED_PACKAGE}"

    while read INSTALLED_PACKAGE
    do
        echo $PKGS_TO_CHECK | grep -q "${INSTALLED_PACKAGE}"
        if [ $? -eq 0 ]; then
            PKGS_TO_CHECK=`echo $PKGS_TO_CHECK | sed "s/^${INSTALLED_PACKAGE} //"`
            PKGS_TO_CHECK=`echo $PKGS_TO_CHECK | sed "s/ ${INSTALLED_PACKAGE} / /"`
            PKGS_TO_CHECK=`echo $PKGS_TO_CHECK | sed "s/ ${INSTALLED_PACKAGE}\$//"`
            PKGS_TO_CHECK=`echo $PKGS_TO_CHECK | sed "s/^${INSTALLED_PACKAGE}\$//"`
        fi
    done < $TMPFILE

    if [ -z "$PKGS_TO_CHECK" ]; then
        >&2 echo "All explicitly specified packages resolved!"
    else
        >&2 echo "Could not resolve packages: $PKGS_TO_CHECK"
        return 1
    fi
    return 0
}

if [ "x${ROOT}" == "x" ]; then
    ROOT=/localdisk/loadbuild/centos
fi

ATTEMPTED=0
DISCOVERED=0
OUTPUT_DIR=${ROOT}/newDisk
YUM=${ROOT}/yum.conf
TMP_DIR=${ROOT}/tmp
DEPLISTFILE=${ROOT}/deps.txt
DEPDETAILLISTFILE=${ROOT}/deps_detail.txt
INSTALLDIR=${ROOT}/newDisk/isolinux/Packages

BUILT_REPORT=${ROOT}/local.txt
WARNINGS_REPORT=${ROOT}/warnings.txt
LAST_TEST=${ROOT}/last_test.txt
TMPFILE=${ROOT}/cgts_deps_tmp.txt
TMPFILE1=${ROOT}/cgts_deps_tmp1.txt

touch "$BUILT_REPORT"
touch "$WARNINGS_REPORT"

for i in "$@"
do
case $i in
    -d=*|--deps=*)
    DEPS="${i#*=}"
    shift # past argument=value
    ;;
esac
done

mkdir -p $TMP_DIR

rm -f "$DEPDETAILLISTFILE"
# FIRST PASS we are being given a list of REQUIRED dependencies
if [ "${DEPS}x" != "x" ]; then
    cat $DEPS | grep -v "^#" > $DEPLISTFILE
    install_deps $DEPLISTFILE
    if [ $? -ne 0 ]; then
        exit 1
    fi
fi

# check that we resolved them all
check_all_explicit_deps_installed
if [ $? -ne 0 ]; then
    >&2 echo "Error -- could not install all explicitly listed packages"
    exit 1
fi

ALL_RESOLVED=0

while [ $ALL_RESOLVED -eq 0 ]; do
    cp $DEPLISTFILE $DEPLISTFILE.old
    generate_dep_list
    if [ ! -s $DEPLISTFILE ]; then
        # no more dependencies!
        ALL_RESOLVED=1
    else
        DIFFLINES=`diff $DEPLISTFILE.old $DEPLISTFILE | wc -l`
        if [ $DIFFLINES -eq 0 ]; then
            >&2 echo "Warning: Infinite loop detected in dependency resolution.  See $DEPLISTFILE for details -- exiting"
            >&2 echo "These RPMS had problems (likely version conflicts)"
            >&2 cat  $DEPLISTFILE

            echo "Warning: Infinite loop detected in dependency resolution See $DEPLISTFILE for details -- exiting" >> $WARNINGS_REPORT
            echo "These RPMS had problems (likely version conflicts)" >> $WARNINGS_REPORT
            cat  $DEPLISTFILE >> $WARNINGS_REPORT

            date > $LAST_TEST

            rm -f $DEPLISTFILE.old
            exit 1 # nothing fixed
        fi
        install_deps $DEPLISTFILE
        if [ $? -ne 0 ]; then
            exit 1
        fi
    fi
done

exit 0
