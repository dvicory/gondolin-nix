#!/bin/sh
set -eu

export PATH=/bin:/sbin

failure_shell() {
  echo "[gondolin-initramfs] ERROR: $1"
  exec sh
}

mkdir -p /proc /sys /dev /run /newroot

mount -t proc proc /proc || failure_shell "failed to mount /proc"
mount -t sysfs sysfs /sys || failure_shell "failed to mount /sys"
mount -t devtmpfs devtmpfs /dev || failure_shell "failed to mount /dev"
mount -t tmpfs tmpfs /run || failure_shell "failed to mount /run"

modprobe virtio_mmio 2>/dev/null || true
modprobe virtio_blk 2>/dev/null || true
modprobe virtio_console 2>/dev/null || true
modprobe ext4 2>/dev/null || true

wait_limit=30
wait_count=0
while [ ! -b /dev/vda ] && [ "$wait_count" -lt "$wait_limit" ]; do
  sleep 1
  wait_count=$((wait_count + 1))
done

[ -b /dev/vda ] || failure_shell "timed out waiting for /dev/vda"

mount -t ext4 /dev/vda /newroot || failure_shell "failed to mount /dev/vda"

mkdir -p /newroot/proc /newroot/sys /newroot/dev /newroot/run
mount --move /proc /newroot/proc || true
mount --move /sys /newroot/sys || true
mount --move /dev /newroot/dev || true
mount --move /run /newroot/run || true

if [ -x /newroot/sbin/init ]; then
  exec switch_root /newroot /sbin/init
fi

if [ -x /newroot/init ]; then
  exec switch_root /newroot /init
fi

if [ -L /newroot/nix/var/nix/profiles/system-1-link ]; then
  system_link_target=$(readlink /newroot/nix/var/nix/profiles/system-1-link || true)
  if [ -n "$system_link_target" ]; then
    # Prefer the stage-2 script: with systemd-in-initrd configs the toplevel
    # `init` is the raw systemd binary and the stage-2 script (which runs the
    # NixOS activation script before exec'ing systemd) lives at
    # `prepare-root`. The NixOS systemd initrd is what normally invokes it;
    # this custom initramfs must do so itself or activation never runs.
    if [ -x "/newroot$system_link_target/prepare-root" ]; then
      exec switch_root /newroot "$system_link_target/prepare-root"
    fi
    if [ -x "/newroot$system_link_target/init" ]; then
      exec switch_root /newroot "$system_link_target/init"
    fi
  fi
fi

failure_shell "no init found"
