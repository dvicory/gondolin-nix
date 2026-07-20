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
    # security.pki bundle cannot include it. Instead, login-shell execs
    # (how agents enter) lazily assemble a combined bundle and export the
    # standard trust variables: OpenSSL/curl/git (SSL_CERT_FILE), Nix tools
    # (NIX_SSL_CERT_FILE), python-requests (REQUESTS_CA_BUNDLE), and Node
    # (NODE_EXTRA_CA_CERTS, additive to its built-in store). Absent the
    # mount (vfs-off guests) everything stays at defaults.
    environment.shellInit = ''
      if [ -r /etc/gondolin/mitm/ca.crt ]; then
        if [ ! -s /run/gondolin-ca/combined.pem ] || [ /etc/gondolin/mitm/ca.crt -nt /run/gondolin-ca/combined.pem ]; then
          mkdir -p /run/gondolin-ca
          cat /etc/ssl/certs/ca-certificates.crt /etc/gondolin/mitm/ca.crt > "/run/gondolin-ca/.combined.$$" 2>/dev/null \
            && mv "/run/gondolin-ca/.combined.$$" /run/gondolin-ca/combined.pem
        fi
        if [ -s /run/gondolin-ca/combined.pem ]; then
          export SSL_CERT_FILE=/run/gondolin-ca/combined.pem
          export NIX_SSL_CERT_FILE="$SSL_CERT_FILE"
          export GIT_SSL_CAINFO="$SSL_CERT_FILE"
          export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
          export NODE_EXTRA_CA_CERTS=/etc/gondolin/mitm/ca.crt
        fi
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
