#!/bin/bash
set -e

if [ -z "$USER" ];then
    export USER="$(id -un)"
fi
export LC_ALL=C
export GAPPS_SOURCES_PATH=vendor/opengapps/sources/

## set defaults

rom_fp="$(date +%y%m%d)"

myname="$(basename "$0")"
if [[ $(uname -s) = "Darwin" ]];then
    jobs=$(sysctl -n hw.ncpu)
elif [[ $(uname -s) = "Linux" ]];then
    jobs=$(nproc)
fi

## handle command line arguments
if [[ -v build_dakkar_choice ]]
then
echo "Using exported choice"
else
read -p "Do you want to sync? (y/N) " build_dakkar_choice
fi
function help() {
    cat <<EOF
Syntax:

  $myname [-j 2] <rom type> <variant>...

Options:

  -j   number of parallel make workers (defaults to $jobs)

ROM types:

  420rom
  aosp10
  lineage171
  pixel100


Variants are dash-joined combinations of (in order):
* processor type
  * "arm" for ARM 32 bit
  * "arm64" for ARM 64 bit
  * "a64" for ARM 32 bit system with 64 bit binder
* A or A/B partition layout ("aonly" or "ab")
* GApps selection
  * "vanilla" to not include GApps
  * "gapps" to include opengapps
  * "go" to include gapps go
  * "floss" to include floss
* SU selection ("su" or "nosu")
* Build variant selection (optional)
  * "eng" for eng build
  * "user" for prod build
  * "userdebug" for debug build (default)

for example:

* arm-aonly-vanilla-nosu-user
* arm64-ab-gapps-su
* a64-aonly-go-nosu
EOF
}

function get_rom_type() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            420rom)
                mainrepo="https://github.com/420rom/android.git"
                mainbranch="420rom-10"
                localManifestBranch="android-10.0"
                treble_generate="420rom"
                extra_make_options="WITHOUT_CHECK_API=true"
                jack_enabled="false"
                ;;
            aosp10)
                mainrepo="https://android.googlesource.com/platform/manifest.git"
                mainbranch="android-10.0.0_r40"
                localManifestBranch="android-10.0"
                treble_generate=""
                extra_make_options=""
                jack_enabled="false"
                ;;
            lineage171)
                mainrepo="https://github.com/LineageOS/android.git"
                mainbranch="lineage-17.1"
                localManifestBranch="android-10.0"
                treble_generate="lineage"
                extra_make_options="WITHOUT_CHECK_API=true"
                jack_enabled="false"
                ;;
            pixel100)
                mainrepo="https://github.com/PixelExperience/manifest.git"
                mainbranch="ten"
                localManifestBranch="android-10.0"
                treble_generate="pixel"
                extra_make_options="WITHOUT_CHECK_API=true"
                jack_enabled="false"
	   
	esac
        shift
    done
}

function parse_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -j)
                jobs="$2";
                shift;
                ;;
        esac
        shift
    done
}

declare -A partition_layout_map
partition_layout_map[aonly]=a
partition_layout_map[ab]=b

declare -A gapps_selection_map
gapps_selection_map[vanilla]=v
gapps_selection_map[gapps]=g
gapps_selection_map[go]=o
gapps_selection_map[floss]=f

declare -A su_selection_map
su_selection_map[su]=S
su_selection_map[nosu]=N

function parse_variant() {
    local -a pieces
    IFS=- pieces=( $1 )

    local processor_type=${pieces[0]}
    local partition_layout=${partition_layout_map[${pieces[1]}]}
    local gapps_selection=${gapps_selection_map[${pieces[2]}]}
    local su_selection=${su_selection_map[${pieces[3]}]}
    local build_type_selection=${pieces[4]}

    if [[ -z "$processor_type" || -z "$partition_layout" || -z "$gapps_selection" || -z "$su_selection" ]]; then
        >&2 echo "Invalid variant '$1'"
        >&2 help
        exit 2
    fi

    echo "treble_${processor_type}_${partition_layout}${gapps_selection}${su_selection}-${build_type_selection}"
}

declare -a variant_codes
declare -a variant_names
function get_variants() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            *-*-*-*-*)
                variant_codes[${#variant_codes[*]}]=$(parse_variant "$1")
                variant_names[${#variant_names[*]}]="$1"
                ;;
            *-*-*-*)
                variant_codes[${#variant_codes[*]}]=$(parse_variant "$1-userdebug")
                variant_names[${#variant_names[*]}]="$1"
                ;;
        esac
        shift
    done
}

## function that actually do things

function init_release() {
    mkdir -p release/"$rom_fp"
}

function init_main_repo() {
    repo init -u "$mainrepo" -b "$mainbranch"
}

function clone_or_checkout() {
    local dir="$1"
    local repo="$2"

    if [[ -d "$dir" ]];then
        (
            cd "$dir"
            git fetch
            git reset --hard
            git checkout origin/"$localManifestBranch"
        )
    else
        git clone https://github.com/phhusson/"$repo" "$dir" -b "$localManifestBranch"
    fi
}

function init_local_manifest() {
    clone_or_checkout .repo/local_manifests treble_manifest
}

download_patches() {
	githubMatch=v2..
    jq --help > /dev/null
	wantedRelease="$(curl --silent https://api.github.com/repos/phhusson/treble_experimentations/releases |jq -r '.[] | .tag_name' |grep -E "$githubMatch\$" |sort -V | tail -n 1)"
	wget "https://github.com/phhusson/treble_experimentations/releases/download/$wantedRelease/patches.zip" -O patches.zip
	rm -Rf patches
	unzip patches.zip -d patches
}

function init_patches() {
    if [[ -n "$treble_generate" ]]; then
	download_patches

        # We don't want to replace from AOSP since we'll be applying
        # patches by hand
        rm -f .repo/local_manifests/replace.xml

        # Remove exfat entry from local_manifest if it exists in ROM manifest 
        if grep -rqF exfat .repo/manifests || grep -qF exfat .repo/manifest.xml;then
            sed -i -E '/external\/exfat/d' .repo/local_manifests/manifest.xml
        fi

        # should I do this? will it interfere with building non-gapps images?
        # rm -f .repo/local_manifests/opengapps.xml
    fi
}

function sync_repo() {
    repo sync -c -j "$jobs" -f --force-sync --no-tag --no-clone-bundle --optimized-fetch --prune
}

function patch_things() {
    if [[ -n "$treble_generate" ]]; then
        rm -f device/*/sepolicy/common/private/genfs_contexts
        (
            cd device/phh/treble
    if [[ $build_dakkar_choice == *"y"* ]];then
            git clean -fdx
    fi
            bash generate.sh "$treble_generate"
        )
        bash "$(dirname "$0")/apply-patches.sh" patches
    else
        (
            cd device/phh/treble
            git clean -fdx
            bash generate.sh
        )
        repo manifest -r > release/"$rom_fp"/manifest.xml
        bash "$(dirname "$0")"/list-patches.sh
        cp patches.zip release/"$rom_fp"/patches.zip
    fi
}

function build_variant() {
    lunch "$1"
    make $extra_make_options BUILD_NUMBER="$rom_fp" installclean
    make $extra_make_options BUILD_NUMBER="$rom_fp" -j "$jobs" systemimage
    make $extra_make_options BUILD_NUMBER="$rom_fp" vndk-test-sepolicy
    cp "$OUT"/system.img release/"$rom_fp"/system-"$2".img
}

function jack_env() {
    RAM=$(free | awk '/^Mem:/{ printf("%0.f", $2/(1024^2))}') #calculating how much RAM (wow, such ram)
    if [[ "$RAM" -lt 16 ]];then #if we're poor guys with less than 16gb
	export JACK_SERVER_VM_ARGUMENTS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx"$((RAM -1))"G"
    fi
}

function clean_build() {
    make installclean
    rm -rf "$OUT"
}

parse_options "$@"
get_rom_type "$@"
get_variants "$@"

if [[ -z "$mainrepo" || ${#variant_codes[*]} -eq 0 ]]; then
    >&2 help
    exit 1
fi

# Use a python2 virtualenv if system python is python3
python=$(python -V | awk '{print $2}' | head -c2)
if [[ $python == "3." ]]; then
    if [ ! -d .venv ]; then
        virtualenv2 .venv
    fi
    . .venv/bin/activate
fi

init_release
if [[ $build_dakkar_choice == *"y"* ]];then
    init_main_repo
    init_local_manifest
    init_patches
    sync_repo
fi

patch_things

if [[ $jack_enabled == "true" ]]; then
    jack_env
fi

if [[ -v build_dakkar_clean ]]
then
echo "Using exported clean choice"
else
read -p "Do you want to clean? (y/N) " build_dakkar_clean
fi

if [[ $build_dakkar_clean == *"y"* ]];then
    clean_build
fi

. build/envsetup.sh

for (( idx=0; idx < ${#variant_codes[*]}; idx++ )); do
    build_variant "${variant_codes[$idx]}" "${variant_names[$idx]}"
done
