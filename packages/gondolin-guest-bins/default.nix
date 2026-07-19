{ lib
, stdenvNoCC
, fetchFromGitHub
, zig
}:

let
  pname = "gondolin-guest-bins";
  version = "0.12.0";

  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "gondolin";
    rev = "v${version}";
    hash = "sha256-H+gIgvaLQq1nurv4OV9RnS8SEglDB2ExY9OZxwzr79k=";
  };
in

# gondolin 0.12.0's guest daemons declare minimum_zig_version 0.16.0 in
# guest/build.zig.zon (they use std.Io.Threaded, which 0.15.x lacks).
# Compile with nixpkgs' zig — one shared package set instead of a
# separately fetched toolchain — and fail closed on an older nixpkgs.
assert lib.assertMsg (lib.versionAtLeast zig.version "0.16.0")
  "gondolin-guest-bins requires zig >= 0.16.0 (got ${zig.version})";

stdenvNoCC.mkDerivation {
  inherit pname version src;

  sourceRoot = "source/guest";

  nativeBuildInputs = [ zig ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export XDG_CACHE_HOME="$TMPDIR"

    zig build -Doptimize=ReleaseSafe

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 zig-out/bin/sandboxd $out/bin/sandboxd
    install -Dm755 zig-out/bin/sandboxfs $out/bin/sandboxfs
    install -Dm755 zig-out/bin/sandboxssh $out/bin/sandboxssh

    runHook postInstall
  '';

  meta = with lib; {
    description = "Gondolin guest control daemons";
    homepage = "https://github.com/earendil-works/gondolin";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
