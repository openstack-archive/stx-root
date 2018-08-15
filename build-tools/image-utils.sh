IMAGE_UTILS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "${IMAGE_UTILS_DIR}/git-utils.sh"

image_inc_list () {

    # build_target: iso, guest ...
    local build_target=$1

    # build_target: std, rt, dev ...
    local build_type=$2

    # build_distro: centos, ...
    local distro=$3

    local root_file=""
    local build_type_extension=""
    local search_target=""

    if [ "${build_type}" != "std" ]; then
         build_type_extension="_${build_type}"
         build_type_extension_bt="-${build_type}"
    fi

    root_file="${MY_REPO}/build-tools/build_${build_target}/image${build_type_extension_bt}.inc"
    search_target=${distro}_${build_target}_image${build_type_extension}.inc

    (
    if [ -f ${root_file} ]; then
        grep '^[^#]' ${root_file}
    fi
    for d in $GIT_LIST; do
        find $d -maxdepth 1 -name "${search_target}" -exec grep '^[^#]' {} +
    done
    ) | sort --unique
}
