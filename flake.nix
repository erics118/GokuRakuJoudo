{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, lib, ... }:
        let
          version = "0.8.1-eric";

          # lein finds ~/.m2 through java's user.home, not $HOME
          leinEnv = ''
            export HOME="$TMPDIR"
            export LEIN_HOME="$HOME/.lein"
            export LEIN_JVM_OPTS="-Duser.home=$HOME"
          '';

          # fixed-output derivation: fetches all maven/clojars deps into an
          # offline .m2 cache. network access is allowed because the output
          # is content-addressed by outputHash
          m2 = pkgs.stdenvNoCC.mkDerivation {
            pname = "goku-m2";
            inherit version;

            src = lib.fileset.toSource {
              root = ./.;
              fileset = ./project.clj;
            };

            nativeBuildInputs = [
              pkgs.jdk_headless
              pkgs.leiningen
            ];

            buildPhase = ''
              runHook preBuild
              ${leinEnv}
              lein -U deps
              # also resolve plugin + uberjar profile deps so the offline
              # build below has everything it needs
              lein -U with-profile +uberjar deps
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              cp -r "$HOME/.m2" "$out"
              # strip non-deterministic metadata that lein writes
              find "$out" -name '_remote.repositories' -delete
              find "$out" -name 'resolver-status.properties' -delete
              runHook postInstall
            '';

            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = "sha256-kkVTv+Qc9T4tNPV3SXF2KFesmpdyOsZ/oItLrzcfZx8=";
          };

          jar = pkgs.stdenvNoCC.mkDerivation {
            pname = "goku-jar";
            inherit version;

            src = ./.;

            nativeBuildInputs = [
              pkgs.jdk_headless
              pkgs.leiningen
            ];

            buildPhase = ''
              runHook preBuild
              ${leinEnv}
              # seed the offline maven cache from the FOD above
              cp -r ${m2} "$HOME/.m2"
              chmod -R u+w "$HOME/.m2"
              export LEIN_OFFLINE=true
              lein uberjar
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              install -Dm644 target/*-standalone.jar "$out/share/java/goku.jar"
              runHook postInstall
            '';
          };

          goku = pkgs.buildGraalvmNativeImage {
            pname = "goku";
            inherit version;

            src = "${jar}/share/java/goku.jar";

            extraNativeImageBuildArgs = [
              "--initialize-at-build-time"
              "--report-unsupported-elements-at-runtime"
              "--no-fallback"
            ];

            meta.mainProgram = "goku";
          };
        in
        {
          packages.default = goku;
          packages.goku = goku;

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              jdk_headless
              leiningen
            ];
          };
        };
    };
}
