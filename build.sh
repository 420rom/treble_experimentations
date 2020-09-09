#!/bin/bash

rom_fp="$(date +%y%m%d)"
originFolder="$(dirname "$0")"
mkdir -p release/$rom_fp/
set -e

if [ -z "$USER" ];then
	export USER="$(id -un)"
fi
export LC_ALL=C


manifest_url="https://android.googlesource.com/platform/manifest"
aosp="android-10.0.0_r45"
phh="420rom-10"

if [ "$release" == true ];then
    [ -z "$version" ] && exit 1
    [ ! -f "$originFolder/release/config.ini" ] && exit 1
fi

repo init -u "$manifest_url" -b $aosp
if [ -d .repo/local_manifests ] ;then
	( cd .repo/local_manifests; git fetch; git reset --hard; git checkout origin/$phh)
else
	git clone https://github.com/420rom/treble_manifest .repo/local_manifests -b $phh
fi
repo sync -c -j 1 --force-sync

repo forall -r '.*opengapps.*' -c 'git lfs fetch && git lfs checkout'
(cd device/phh/treble; git clean -fdx; bash generate.sh)
(cd vendor/foss; git clean -fdx; bash update.sh)
rm -f vendor/gapps/interfaces/wifi_ext/Android.bp

. build/envsetup.sh

buildVariant() {
	lunch $1
	make BUILD_NUMBER=$rom_fp installclean
	make BUILD_NUMBER=$rom_fp -j8 systemimage
	make BUILD_NUMBER=$rom_fp vndk-test-sepolicy
	xz -c $OUT/system.img -T0 > release/$rom_fp/system-${2}.img.xz
}

repo manifest -r > release/$rom_fp/manifest.xml
bash "$originFolder"/list-patches.sh
cp patches.zip release/$rom_fp/patches.zip

buildVariant treble_arm64_agN-userdebug quack-arm64-aonly-gapps-nosu

if [ "$release" == true ];then
    (
        rm -Rf venv
        pip install virtualenv
        export PATH=$PATH:~/.local/bin/
        virtualenv -p /usr/bin/python3 venv
        source venv/bin/activate
        pip install -r $originFolder/release/requirements.txt

        name="AOSP 10.0"
        [ "$1" == "android-10.0" ] && name="AOSP 10.0"
        python $originFolder/release/push.py "$name" "$version" release/$rom_fp/
        rm -Rf venv
    )
fi
