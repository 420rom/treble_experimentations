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
aosp="android-11.0.0_r37"
phh="420rom-11"

if [ "$release" == true ];then
    [ -z "$version" ] && exit 1
    [ ! -f "$originFolder/release/config.ini" ] && exit 1
fi

if [ -n "$rebuild_release" ];then
	repo init -u "$tmp_manifest_source" -m manifest.xml
else
	repo init -u "$manifest_url" -b $aosp
	if [ -d .repo/local_manifests ] ;then
		( cd .repo/local_manifests; git fetch; git reset --hard; git checkout origin/$phh)
	else
		git clone ssh://git@github.com/420rom/treble_manifest .repo/local_manifests -b 420rom-11
	fi
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

if [ "$build_target" == "android-11.0" ];then
    (
        git clone ssh://git@github.com/phhusson/sas-creator
        cd sas-creator

        git clone ssh://git@github.com/phhusson/vendor_vndk -b android-10.0
    )

    # ARM64 Gapps {ab, a-only, ab vndk lite}
	buildVariant treble_arm64_bgS-userdebug roar-arm64-ab-gapps
    ( cd sas-creator; bash run.sh 64 ; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-aonly-gapps.img.xz)
    ( cd sas-creator; bash lite-adapter.sh 64; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-ab-vndklite-gapps.img.xz )
    
    # ARM64 vanilla {ab, a-only, ab vndk lite}
	buildVariant treble_arm64_bvS-userdebug roar-arm64-ab-vanilla
    ( cd sas-creator; bash run.sh 64 ; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-aonly-vanilla.img.xz)
    ( cd sas-creator; bash lite-adapter.sh 64; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-ab-vndklite-vanilla.img.xz )

    # ARM64 floss {ab, a-only, ab vndk lite}
	buildVariant treble_arm64_bfS-userdebug roar-arm64-ab-floss
    ( cd sas-creator; bash run.sh 64 ; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-aonly-floss.img.xz)
    ( cd sas-creator; bash lite-adapter.sh 64; xz -c s.img -T0 > ../release/$rom_fp/system-roar-arm64-ab-vndklite-floss.img.xz )


elif [ "$build_target" == "android-10.0" ];then
	buildVariant treble_arm64_bgS-userdebug quack-arm64-ab-gapps
	buildVariant treble_arm64_bfS-userdebug quack-arm64-ab-floss
	buildVariant treble_arm64_bvS-userdebug quack-arm64-ab-vanilla
	buildVariant treble_arm64_afS-userdebug quack-arm64-aonly-floss
	buildVariant treble_arm64_avS-userdebug quack-arm64-aonly-vanilla
	buildVariant treble_arm64_agS-userdebug quack-arm64-aonly-gapps
	buildVariant treble_arm64_aoS-userdebug quack-arm64-aonly-go
else
	buildVariant treble_arm64_avN-userdebug arm64-aonly-vanilla-nosu
	buildVariant treble_arm64_agS-userdebug arm64-aonly-gapps-su
	#buildVariant treble_arm64_afS-userdebug arm64-aonly-floss-su
	rm -Rf out/target/product/phhgsi*

	buildVariant treble_arm64_bvN-userdebug arm64-ab-vanilla-nosu
	buildVariant treble_arm64_bgS-userdebug arm64-ab-gapps-su
	#buildVariant treble_arm64_bfS-userdebug arm64-ab-floss-su
	rm -Rf out/target/product/phhgsi*

	buildVariant treble_arm_avN-userdebug arm-aonly-vanilla-nosu
	[ "$build_target" != "android-9.0" ] && buildVariant treble_arm_aoS-userdebug arm-aonly-go-su
	buildVariant treble_arm_agS-userdebug arm-aonly-gapps-su
	rm -Rf out/target/product/phhgsi*

	buildVariant treble_a64_avN-userdebug arm32_binder64-aonly-vanilla-nosu
	buildVariant treble_a64_agS-userdebug arm32_binder64-aonly-gapps-su
	rm -Rf out/target/product/phhgsi*

	if [ "$build_target" == "android-9.0" ];then
	buildVariant treble_a64_bvN-userdebug arm32_binder64-ab-vanilla-nosu
	buildVariant treble_a64_bgS-userdebug arm32_binder64-ab-gapps-su
	fi
	rm -Rf out/target/product/phhgsi*
fi

if [ "$release" == true ];then
    (
        rm -Rf venv
        pip install virtualenv
        export PATH=$PATH:~/.local/bin/
        virtualenv -p /usr/bin/python3 venv
        source venv/bin/activate
        pip install -r $originFolder/release/requirements.txt

        name="AOSP 8.1"
        [ "$build_target" == "android-9.0" ] && name="AOSP 9.0"
        python $originFolder/release/push.py "$name" "$version" release/$rom_fp/
        rm -Rf venv
    )
fi
