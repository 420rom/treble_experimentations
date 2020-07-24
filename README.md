# 420rom AOSP/Pixel based rom

Getting Started

To get started with Android/420rom, you'll need to get familiar with Git and Repo.

To initialize your local repository using the 420rom trees, use a command like this:

repo init -u git://github.com/420rom/android.git -b 420rom-10

# How to build

* clone this repository
* call the build scripts from a separate directory

For example:

    git clone https://github.com/420rom/treble_experimentations
    mkdir 420rom; cd 420rom
    bash ../treble_experimentations/build-rom.sh android-10.0 420rom

# More flexible build script

(this has been tested much less)

  bash ../treble_experimentations/build-dakkar.sh 420rom \
    arm64-aonly-gapps-nosu \
    arm64-ab-go-nosu

The script should provide a help message if you pass something it
doesn't understand

# Using Docker

clone this repository, then:

    docker build -t treble docker/
    
    docker container create --name treble treble
    
    docker run -ti \
        -v $(pwd):/treble \
        -v $(pwd)/../treble_output:/treble_output \
        -w /treble_output \
        treble \
        /bin/bash /treble/build-dakkar.sh 420rom \
        arm64-aonly-gapps-nosu \
        arm64-ab-go-nosu
