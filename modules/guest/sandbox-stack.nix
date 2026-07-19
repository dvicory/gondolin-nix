{ lib, config, pkgs, gondolinPackages ? null, ... }:

let
  cfg = config.virtualisation.gondolin.guest;

  gondolinGuestBins =
    if gondolinPackages != null && builtins.hasAttr "gondolin-guest-bins" gondolinPackages then
      gondolinPackages."gondolin-guest-bins"
    else
      throw "virtualisation.gondolin.guest requires specialArgs.gondolinPackages.\"gondolin-guest-bins\"";

  script = pkgs.writeShellScript "gondolin-sandbox-stack" ''
    set -eu

    wait_for_node() {
      node="$1"
      i=0
      while [ "$i" -lt 30 ]; do
        if [ -e "$node" ]; then
          return 0
        fi
        i=$((i + 1))
        sleep 1
      done
      echo "[gondolin-sandbox-stack] timed out waiting for $node" >&2
      return 1
    }

    sandboxfs_mount="/data"
    sandboxfs_binds=""

    if [ -r /proc/cmdline ]; then
      for arg in $(cat /proc/cmdline); do
        case "$arg" in
          sandboxfs.mount=*)
            sandboxfs_mount="''${arg#sandboxfs.mount=}"
            ;;
          sandboxfs.bind=*)
            sandboxfs_binds="''${arg#sandboxfs.bind=}"
            ;;
        esac
      done
    fi

    wait_for_sandboxfs_mount() {
      i=0
      while [ "$i" -lt 30 ]; do
        if grep -q " $sandboxfs_mount fuse.sandboxfs " /proc/mounts; then
          return 0
        fi
        i=$((i + 1))
        sleep 1
      done
      return 1
    }

    wait_for_node /dev/virtio-ports/virtio-port
    wait_for_node /dev/virtio-ports/virtio-fs

    mkdir -p "$sandboxfs_mount"

    ${gondolinGuestBins}/bin/sandboxfs --mount "$sandboxfs_mount" --rpc-path /dev/virtio-ports/virtio-fs &

    if wait_for_sandboxfs_mount && [ -n "$sandboxfs_binds" ]; then
      old_ifs="$IFS"
      IFS=','
      for bind in $sandboxfs_binds; do
        [ -n "$bind" ] || continue
        mkdir -p "$bind"

        if [ "$sandboxfs_mount" = "/" ]; then
          bind_source="$bind"
        else
          bind_source="$sandboxfs_mount$bind"
        fi

        ${pkgs.util-linux}/bin/mount --bind "$bind_source" "$bind"
      done
      IFS="$old_ifs"
    fi

    exec ${gondolinGuestBins}/bin/sandboxd
  '';
in
lib.mkIf cfg.enable {
  systemd.tmpfiles.rules = [
    "L+ /bin/sh - - - - ${pkgs.bash}/bin/sh"
    "L+ /bin/bash - - - - ${pkgs.bashInteractive}/bin/bash"
    "L+ /bin/true - - - - ${pkgs.coreutils}/bin/true"
  ];

  systemd.services.gondolin-sandbox-stack = {
    description = "Gondolin guest daemon compatibility stack";
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    after = [
      "local-fs.target"
      "systemd-udevd.service"
      "systemd-modules-load.service"
    ];
    wants = [
      "systemd-udevd.service"
      "systemd-modules-load.service"
    ];

    serviceConfig = {
      Type = "simple";
      ExecStart = script;
      Restart = "on-failure";
      RestartSec = "2s";
      # Forward stack stderr/stdout to the serial console so sandboxfs and
      # sandboxd failures are visible in the host-side QEMU log.
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };
}
