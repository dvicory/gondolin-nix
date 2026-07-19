{ lib, pkgs }:

{
  mkGuestRootfs =
    { config
    , rootfsLabel ? "gondolin-root"
    , diskSizeMb ? null
    }:
    let
      toplevelClosure = pkgs.closureInfo { rootPaths = [ config.system.build.toplevel ]; };
    in
    pkgs.runCommand "gondolin-rootfs.img"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.e2fsprogs
          pkgs.gnutar
        ];
      } ''
      set -euo pipefail

      root="$TMPDIR/root"
      mkdir -p "$root/nix/store" "$root/nix/var/nix/profiles"

      while IFS= read -r p; do
        [ -n "$p" ] || continue
        rel="''${p#/}"
        (cd / && tar -cpf - "$rel") | (cd "$root" && tar -xpf - --no-same-owner)
      done < ${toplevelClosure}/store-paths

      ln -s ${config.system.build.toplevel} "$root/nix/var/nix/profiles/system-1-link"
      ln -s system-1-link "$root/nix/var/nix/profiles/system"

      # The guest boot path executes the toplevel init directly; nothing
      # else populates /etc. Copy the toplevel /etc tree (units, os-release,
      # profile fragments) so systemd finds its unit files at boot. cp -a
      # preserves the absolute /nix/store symlinks, which resolve inside the
      # guest because the store is in the rootfs.
      cp -a ${config.system.build.etc}/etc "$root/etc"
      chmod -R u+w "$root/etc"
      touch "$root/etc/NIXOS"

      if [ -n "${if diskSizeMb == null then "" else toString diskSizeMb}" ]; then
        size_mb="${if diskSizeMb == null then "" else toString diskSizeMb}"
      else
        used_kb="$(du -s --apparent-size "$root" | cut -f1)"
        size_mb=$(( (used_kb * 13 / 10) / 1024 + 512 ))
      fi

      img="$TMPDIR/rootfs.img"
      truncate -s "''${size_mb}M" "$img"
      mkfs.ext4 -F -i 4096 -L ${lib.escapeShellArg rootfsLabel} -d "$root" "$img"

      cp "$img" "$out"
    '';
}
