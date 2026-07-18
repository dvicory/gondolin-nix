{ lib, pkgs }:

{
  mkGuestAssetsManifest =
    { arch
    , rootfsLabel
    , diskSizeMb ? null
    , kernelPath
    , initramfsPath
    , rootfsPath
    }:
    let
      manifestConfigJson = builtins.toJSON {
        inherit arch;
        distro = "nixos";
        rootfs =
          { label = rootfsLabel; }
          // lib.optionalAttrs (diskSizeMb != null) { sizeMb = diskSizeMb; };
      };
    in
    pkgs.runCommand "gondolin-assets" { } ''
      set -euo pipefail

      checksum_file() {
        local file="$1"
        ${pkgs.coreutils}/bin/sha256sum "$file" | ${pkgs.coreutils}/bin/cut -d ' ' -f1
      }

      mkdir -p "$out"

      ln -s "${kernelPath}" "$out/vmlinuz-virt"
      ln -s "${initramfsPath}" "$out/initramfs.cpio.lz4"
      ln -s "${rootfsPath}" "$out/rootfs.ext4"

      kernel_checksum="$(checksum_file "$out/vmlinuz-virt")"
      initramfs_checksum="$(checksum_file "$out/initramfs.cpio.lz4")"
      rootfs_checksum="$(checksum_file "$out/rootfs.ext4")"

      source_date_epoch="''${SOURCE_DATE_EPOCH:-1}"
      build_time="$(${pkgs.coreutils}/bin/date -u -d "@$source_date_epoch" +%Y-%m-%dT%H:%M:%SZ)"

      # Deterministic, content-derived build ID using the exact semantics of
      # Gondolin's computeAssetBuildId: UUIDv5 (RFC 4122, SHA-1) over the
      # newline-joined asset checksums and arch in a fixed namespace. The guest
      # helper stack and manifest configuration are covered transitively
      # because every guest module knob flows into one of the three artifact
      # checksums.
      build_id="$(
        GONDOLIN_KERNEL_SUM="$kernel_checksum" \
        GONDOLIN_INITRAMFS_SUM="$initramfs_checksum" \
        GONDOLIN_ROOTFS_SUM="$rootfs_checksum" \
        GONDOLIN_ARCH="${arch}" \
        ${pkgs.python3}/bin/python3 -c '
      import os, uuid
      ns = uuid.UUID("7b6ed0c0-7e7f-4c2a-8b2d-0bf3d5be9d52")
      name = "\n".join([
          "gondolin-asset-build",
          "kernel=" + os.environ["GONDOLIN_KERNEL_SUM"],
          "initramfs=" + os.environ["GONDOLIN_INITRAMFS_SUM"],
          "rootfs=" + os.environ["GONDOLIN_ROOTFS_SUM"],
          "arch=" + os.environ["GONDOLIN_ARCH"],
      ])
      print(uuid.uuid5(ns, name))
      '
      )"

      # TODO(gondolin-nix): add optional support for runtimeDefaults/ociSource
      # and schema-backed validation in checks.
      ${pkgs.jq}/bin/jq -n \
        --arg buildId "$build_id" \
        --arg kernel "vmlinuz-virt" \
        --arg initramfs "initramfs.cpio.lz4" \
        --arg rootfs "rootfs.ext4" \
        --arg kernelChecksum "$kernel_checksum" \
        --arg initramfsChecksum "$initramfs_checksum" \
        --arg rootfsChecksum "$rootfs_checksum" \
        --arg buildTime "$build_time" \
        --argjson config '${manifestConfigJson}' \
        '{
          version: 1,
          buildId: $buildId,
          buildTime: $buildTime,
          config: $config,
          assets: {
            kernel: $kernel,
            initramfs: $initramfs,
            rootfs: $rootfs
          },
          checksums: {
            kernel: $kernelChecksum,
            initramfs: $initramfsChecksum,
            rootfs: $rootfsChecksum
          }
        }' > "$out/manifest.json"
    '';
}
