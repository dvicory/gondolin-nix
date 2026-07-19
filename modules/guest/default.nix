{ lib, config, pkgs, gondolinPackages ? null, ... }:

let
  cfg = config.virtualisation.gondolin.guest;
in
{
  imports = [
    ./assets
    ./sandbox-stack.nix
  ];

  options.virtualisation.gondolin.guest = {
    enable = lib.mkEnableOption "Gondolin guest profile";

    rootfsLabel = lib.mkOption {
      type = lib.types.str;
      default = "gondolin-root";
      description = "Root filesystem label for the Gondolin guest image.";
    };

    diskSizeMb = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Optional fixed rootfs size in MiB.";
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems."/" = {
      device = lib.mkDefault "/dev/disk/by-label/${cfg.rootfsLabel}";
      fsType = lib.mkDefault "ext4";
    };

    boot.loader.grub.devices = lib.mkDefault [ "/dev/vda" ];
    system.stateVersion = lib.mkDefault "25.11";

    # Baseline userland for guest shells and execs. The guest never runs
    # NixOS system activation, so /run/current-system (which /etc/profile
    # puts on PATH) is wired up via the tmpfiles links below instead.
    environment.systemPackages = with pkgs; [
      coreutils
      curl
      findutils
      gawk
      git
      gnugrep
      gnused
      iproute2
      iputils
      procps
      util-linux
    ];

    systemd.tmpfiles.rules = [
      # Indirect through the profile link the rootfs builder creates;
      # referencing config.system.build.toplevel here would recurse
      # (tmpfiles rules contribute to the toplevel derivation itself).
      "L+ /run/current-system - - - - /nix/var/nix/profiles/system"
      "L+ /run/booted-system - - - - /nix/var/nix/profiles/system"
      "d /root 0700 root root -"
    ];

    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "virtualisation.gondolin.guest is currently supported on Linux only.";
      }
      {
        assertion = gondolinPackages != null && builtins.hasAttr "gondolin-guest-bins" gondolinPackages;
        message = "virtualisation.gondolin.guest requires specialArgs.gondolinPackages.\"gondolin-guest-bins\"";
      }
    ];
  };
}
