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

    # The guest never runs NixOS system activation, which is what normally
    # provisions /etc/passwd, /etc/group, and /etc/shadow. Without those,
    # every unit that runs as a system user fails at USER-spawning
    # (dhcpcd, dbus-broker, nscd, systemd-timesyncd, ...), which takes down
    # guest networking among other things. Immutable users bake the account
    # files statically into the /etc tree instead.
    users.mutableUsers = false;
    # Nobody logs into a disposable sandbox: no passwords, no SSH keys.
    # Guest access is exclusively the sandboxd exec channel, so the
    # lockout this assertion guards against is precisely what we want.
    users.allowNoPasswordLogin = true;

    # Baseline userland for guest shells and execs.
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

    # Trust the SDK-provided MITM CA for hook-mediated egress. The CA is
    # dynamic (host-generated per cert dir) and only exists at runtime,
    # mounted read-only at /etc/gondolin/mitm/ca.crt — the build-time
    # security.pki bundle cannot include it. Retarget the canonical
    # system bundle symlinks at a runtime-assembled combined bundle
    # (static bundle + MITM CA) so every tool that resolves the system
    # trust store — curl (incl. CURL_CA_BUNDLE), git, OpenSSL — trusts the
    # mediation without per-tool env spray. The stack service seeds the
    # combined file at boot; login shells refresh it when the MITM mount
    # lands after boot. Only stores that never consult system paths keep
    # explicit variables: python-requests/certifi and Node.
    environment.etc."ssl/certs/ca-certificates.crt".source = lib.mkForce "/run/gondolin-ca/combined.pem";
    environment.etc."ssl/certs/ca-bundle.crt".source = lib.mkForce "/run/gondolin-ca/combined.pem";
    environment.etc."pki/tls/certs/ca-bundle.crt".source = lib.mkForce "/run/gondolin-ca/combined.pem";

    environment.shellInit = ''
      if [ -r /etc/gondolin/mitm/ca.crt ]; then
        if [ ! -s /run/gondolin-ca/combined.pem ] || [ /etc/gondolin/mitm/ca.crt -nt /run/gondolin-ca/combined.pem ]; then
          mkdir -p /run/gondolin-ca
          cat ${config.security.pki.caBundle} /etc/gondolin/mitm/ca.crt > "/run/gondolin-ca/.combined.$$" 2>/dev/null \
            && mv "/run/gondolin-ca/.combined.$$" /run/gondolin-ca/combined.pem
        fi
      fi
      if [ -s /run/gondolin-ca/combined.pem ]; then
        export REQUESTS_CA_BUNDLE=/run/gondolin-ca/combined.pem
        export NODE_EXTRA_CA_CERTS=/etc/gondolin/mitm/ca.crt
      fi
    '';

    systemd.tmpfiles.rules = [
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
