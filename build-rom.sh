#!/bin/bash

rom_fp="$(date +%y%m%d)"
originFolder="$(dirname "$0")"
mkdir -p release/$rom_fp/
set -e

if [ "$#" -le 1 ];then
	echo "Usage: $0 <android-11.0> <lineage|420rom> '# of jobs'"
	exit 0
fi
localManifestBranch=$1
rom=$2

if [ "$release" == true ];then
    [ -z "$version" ] && exit 1
    [ ! -f "$originFolder/release/config.ini" ] && exit 1
fi

if [ -z "$USER" ];then
	export USER="$(id -un)"
fi
export LC_ALL=C

if [[ -n "$3" ]];then
	jobs=$3
else
    if [[ $(uname -s) = "Darwin" ]];then
        jobs=$(sysctl -n hw.ncpu)
    elif [[ $(uname -s) = "Linux" ]];then
        jobs=$(nproc)
    fi
fi

#We don't want to replace from AOSP since we'll be applying patches by hand
rm -f .repo/local_manifests/replace.xml
if [ "$rom" == "lineage15" ];then
	repo init -u ssh://git@github.com/LineageOS/android.git -b lineage-15.1
elif [ "$rom" == "lineage16" ];then
	repo init -u ssh://git@github.com/LineageOS/android.git -b lineage-16.0
elif [ "$rom" == "lineage18" ];then
	repo init -u ssh://git@github.com/LineageOS/android.git -b lineage-18.0
elif [ "$rom" == "420rom-11" ];then
	repo init -u ssh://git@github.com/420rom/android.git -b 420rom-11
fi

if [ -d .repo/local_manifests ] ;then
	( cd .repo/local_manifests; git fetch; git checkout origin/420rom-11)
else
	git clone ssh://git@github.com/420rom/treble_manifest .repo/local_manifests -b 420rom-11
fi

file="patches.zip"
if [ -f $file ] ; then
    rm $file
fi

folder="patches"
if [ -f $folder ] ; then
    rm -rf $folder
fi

mkdir patches
wget ssh://git@github.com/phhusson/treble_experimentations/releases/download/v306/patches.zip
unzip  patches.zip -d patches

#We don't want to replace from AOSP since we'll be applying patches by hand
rm -f .repo/local_manifests/replace.xml

repo sync -c -j$jobs --force-sync
rm -f device/*/sepolicy/common/private/genfs_contexts
(cd device/phh/treble; git clean -fdx; bash generate.sh $rom)

sed -i -e 's/BOARD_SYSTEMIMAGE_PARTITION_SIZE := 1610612736/BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2147483648/g' device/phh/treble/phhgsi_arm64_a/BoardConfig.mk

bash "$(dirname "$0")/apply-patches.sh" patches

. build/envsetup.sh

buildVariant() {
	lunch $1
	make WITHOUT_CHECK_API=true BUILD_NUMBER=$rom_fp installclean
	make WITHOUT_CHECK_API=true BUILD_NUMBER=$rom_fp -j$jobs systemimage
	make WITHOUT_CHECK_API=true BUILD_NUMBER=$rom_fp vndk-test-sepolicy
	xz -c $OUT/system.img -T$jobs > release/$rom_fp/system-${2}.img.xz
}

repo manifest -r > release/$rom_fp/manifest.xml
buildVariant treble_arm64_avN-userdebug arm64-aonly-vanilla-nosu
buildVariant treble_arm64_avS-userdebug arm64-aonly-vanilla-su
buildVariant treble_arm64_agS-userdebug arm64-aonly-gapps-su
buildVariant treble_arm64_agN-userdebug arm64-aonly-gapps-nosu
buildVariant treble_arm64_bvN-userdebug arm64-ab-vanilla-nosu
buildVariant treble_arm64_bvS-userdebug arm64-ab-vanilla-su
buildVariant treble_arm64_bgS-userdebug arm64-ab-gapps-su
buildVariant treble_arm64_bgN-userdebug arm64-ab-gapps-nosu
buildVariant treble_arm_avN-userdebug arm-aonly-vanilla-nosu
buildVariant treble_arm_aoS-userdebug arm-aonly-gapps
buildVariant treble_a64_avN-userdebug arm32_binder64-aonly-vanilla-nosu
buildVariant treble_a64_agS-userdebug arm32_binder64-aonly-gapps-su

if [ "$release" == true ];then
    (
        rm -Rf venv
        pip install virtualenv
        export PATH=$PATH:~/.local/bin/
        virtualenv -p /usr/bin/python3 venv
        source venv/bin/activate
        pip install -r $originFolder/release/requirements.txt

        python $originFolder/release/push.py "${rom^}" "$version" release/$rom_fp/
        rm -Rf venv
    )
fi
