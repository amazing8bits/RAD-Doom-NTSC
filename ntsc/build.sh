#!/bin/bash
#
# Rebuilds the RAD-Doom NTSC kernels from this repository, using the toolchain,
# Circle version and Circle configuration that reproduce the official
# RAD-Doom v01 kernels (see NTSC.md for why each of these matters).
#
# usage: ntsc/build.sh [parent-dir]
#
# A build tree whose path is exactly 30 characters long is created inside
# parent-dir (default: $HOME). The four kernels end up in ntsc/out/.
#
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PARENT=$(cd "${1:-$HOME}" && pwd)
OUT=$REPO/ntsc/out

CIRCLE_STDLIB_TAG=15.14
CIRCLE_SHA=6a6e37586c4b2dbce4a3a0beef57d669c3026f86     # Circle Step45
NEWLIB_SHA=343aa5863161befa0c4d15575c4deda4f0ade0dd
GCC=gcc-arm-10.3-2021.07-x86_64-aarch64-none-elf
GCC_URL=https://developer.arm.com/-/media/Files/downloads/gnu-a/10.3-2021.07/binrel/$GCC.tar.xz

# The official kernels were built in /mnt/c/Work/Code/circle-stdlib. newlib
# embeds its source paths (__FILE__), so the length of the tree path moves
# data in the kernel. A tree of the same length keeps the layout identical to
# the official kernels (boot tests showed layout changes are harmless, so this
# only matters for byte-identical builds).
TREE_LEN=30
n=$(( TREE_LEN - ${#PARENT} - 1 ))
if [ $n -lt 4 ]; then
	echo "parent directory '$PARENT' is too long, use one with at most $(( TREE_LEN - 5 )) characters (e.g. /tmp)"
	exit 1
fi
TREE=$PARENT/$(printf '%-*s' $n raddoom-ntsc | tr ' ' '_' | cut -c1-$n)

# toolchain: gcc 10.3-2021.07 (other versions produce different code)
if ! aarch64-none-elf-gcc --version 2>/dev/null | grep -q '10.3-2021.07'; then
	for d in "/opt/$GCC" "$PARENT/$GCC"; do
		[ -x "$d/bin/aarch64-none-elf-gcc" ] && { export PATH=$d/bin:$PATH; break; }
	done
fi
if ! aarch64-none-elf-gcc --version 2>/dev/null | grep -q '10.3-2021.07'; then
	echo "downloading $GCC to $PARENT"
	curl -fL "$GCC_URL" | tar xJ -C "$PARENT"
	export PATH=$PARENT/$GCC/bin:$PATH
fi
echo "compiler: $(command -v aarch64-none-elf-gcc)"
echo "build tree: $TREE"

# circle-stdlib + Circle Step45 + circle-newlib, with the RAD-Doom Circle changes
if [ ! -d "$TREE" ]; then
	tmp=$(mktemp -d)
	curl -fsSL "https://github.com/smuehlst/circle-stdlib/archive/refs/tags/v$CIRCLE_STDLIB_TAG.tar.gz" | tar xz -C "$tmp"
	curl -fsSL "https://github.com/rsta2/circle/archive/$CIRCLE_SHA.tar.gz" | tar xz -C "$tmp"
	curl -fsSL "https://github.com/smuehlst/circle-newlib/archive/$NEWLIB_SHA.tar.gz" | tar xz -C "$tmp"
	S=$tmp/circle-stdlib-$CIRCLE_STDLIB_TAG
	rmdir "$S/libs/circle" "$S/libs/circle-newlib"
	mv "$tmp/circle-$CIRCLE_SHA" "$S/libs/circle"
	mv "$tmp/circle-newlib-$NEWLIB_SHA" "$S/libs/circle-newlib"
	patch -d "$S/libs/circle" -p1 < "$REPO/ntsc/circle45-raddoom.patch"
	mv "$S" "$TREE"
	rm -rf "$tmp"
fi

cd "$TREE"
LIBS="libs/circle/lib/libcircle.a libs/circle/lib/usb/libusb.a libs/circle/lib/input/libinput.a
      libs/circle/lib/fs/libfs.a libs/circle/lib/net/libnet.a libs/circle/lib/sched/libsched.a
      libs/circle/addon/SDCard/libsdcard.a libs/circle/addon/fatfs/libfatfs.a
      install/aarch64-none-circle/lib/libc.a"
if ! ls $LIBS > /dev/null 2>&1; then
	echo "building Circle and newlib (takes a while, logs in $TREE)"
	mkdir -p build/circle-newlib
	./configure -r 3 -p aarch64-none-elf- > configure.log 2>&1
	# the wlan addon fails to build with this combination; RAD-Doom does not use it
	make -j"$(nproc)" MAKEINFO=true circle > circle.log 2>&1 || true
	make -j"$(nproc)" MAKEINFO=true newlib > newlib.log 2>&1
	ls $LIBS > /dev/null
fi

# RAD-Doom (the Makefile expects to sit in <circle-stdlib>/RAD-Doom/Source)
rm -rf RAD-Doom
mkdir RAD-Doom
cp -a "$REPO/Source" RAD-Doom/
cd RAD-Doom/Source
mkdir -p "$OUT"

variant() {
	local img=$1; shift
	cp "$REPO/Source/rad_doom_defs.h" rad_doom_defs.h
	for expr in "$@"; do
		sed -i "$expr" rad_doom_defs.h
	done
	make clean > /dev/null 2>&1
	if ! make -j"$(nproc)" > "make_$img.log" 2>&1; then
		tail -20 "make_$img.log"
		exit 1
	fi
	cp kernel8.img "$OUT/$img"
	echo "built $img"
}

variant kernel_doom_ntsc.img
variant kernel_doom_midi_sequential_ntsc.img 's|^//#define USE_MIDI|#define USE_MIDI|'
variant kernel_doom_midi_datel_ntsc.img      's|^//#define USE_MIDI|#define USE_MIDI|' \
                                             's|^#define MIDI_ADDRESS    0xDE00|#define MIDI_ADDRESS    0xDE04|'
variant kernel_doom_digimax_ntsc.img         's|^//#define USE_DIGIMAX|#define USE_DIGIMAX|'

ls -l "$OUT"
