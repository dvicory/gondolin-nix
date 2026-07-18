{ lib
, stdenvNoCC
, fetchurl
, nodejs_22
, cacert
, makeWrapper
, qemu
}:

let
  version = "0.12.0";
  pname = "gondolin";

  src = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/gondolin/-/gondolin-${version}.tgz";
    hash = "sha256-J61m91/naoSDiCkfohjprJrG2sR7moGKP8xYkBaj+eI=";
  };

  # The upstream tarball ships a compiled dist/ but no lockfile. We vendor a
  # package-lock.json (generated with nixpkgs nodejs_22's npm) so the
  # fixed-output node_modules tree stays reproducible when the npm registry
  # publishes new semver-compatible releases of the floating ^ dependencies.
  node_modules = stdenvNoCC.mkDerivation {
    pname = "${pname}-node_modules";
    inherit version;

    dontUnpack = true;

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];

    nativeBuildInputs = [ nodejs_22 cacert ];

    buildPhase = ''
      runHook preBuild

      export HOME=$TMPDIR
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt

      mkdir pkg
      tar -xzf ${src} -C pkg --strip-components=1
      cp ${./package-lock.json} pkg/package-lock.json

      cd pkg
      ${nodejs_22}/bin/npm ci \
        --omit=dev \
        --ignore-scripts \
        --cache $TMPDIR/npm-cache \
        --no-update-notifier \
        --no-fund \
        --no-audit

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/node_modules/@earendil-works
      cp -r . $out/lib/node_modules/@earendil-works/gondolin

      runHook postInstall
    '';

    dontFixup = true;

    # Per-platform hashes: the optional @earendil-works/gondolin-krun-runner-*
    # packages install platform-specific prebuilt binaries. The non-native hash
    # can be recomputed on any host with:
    #   npm ci --omit=dev --ignore-scripts --os=<os> --cpu=<cpu> --libc=glibc
    # followed by `nix hash path --sri` on the staged output layout.
    outputHash = {
      "aarch64-darwin" = "sha256-mukm3NUdyJF/uCx0n4OKTnz1Ex3PNkGEFHRQUuGrlH4=";
      "x86_64-linux" = "sha256-5KxGxa5z6ulSUUiI20/23MlX/WFJ4rNjP+6prQIf00E=";
    }.${stdenvNoCC.system};
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules
    cp -r ${node_modules}/lib/node_modules/@earendil-works $out/lib/node_modules/

    mkdir -p $out/bin
    makeWrapper ${nodejs_22}/bin/node $out/bin/gondolin \
      --add-flags "$out/lib/node_modules/@earendil-works/gondolin/dist/bin/gondolin.js" \
      --set NODE_PATH "$out/lib/node_modules" \
      --prefix PATH : ${lib.makeBinPath [ qemu ]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Local Linux micro-VM sandbox with programmable network and filesystem";
    homepage = "https://github.com/earendil-works/gondolin";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = [ "aarch64-darwin" "x86_64-linux" ];
    mainProgram = "gondolin";
  };
}
