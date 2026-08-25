# Description: this file implements build helpers
# for MirageOS unikernels <https://mirageos.org>.
{
  coreutils,
  jq,
  lib,
  nix,
  opam-nix,
  stdenv,
  writeShellApplication,
  writeText,
}:

let
  excludeDrvArgNames = [
    "target"
    "targets"
    "materializedDir"
    "overrideUnikernel"
    "query"
    "queryArgs"
    "monorepoQuery"
    "monorepoQueryArgs"
    "opamPackages"
    "mirageDir"
  ];
in

rec {
  # Description: run `mirage configure` on source,
  # to generate dune recipes to build the unikernel for given `target`.
  configure = lib.extendMkDerivation {
    constructDrv = stdenv.mkDerivation;
    inherit excludeDrvArgNames;
    extendDrvArgs =
      finalAttrs:
      {
        pname,
        target,
        opamPackages,
        mirageDir ? finalAttrs.mirageDir or ".",
        ...
      }:
      {
        name = "mirage-${pname}-${target}";
        buildInputs = with opamPackages; [ mirage ];
        nativeBuildInputs = with opamPackages; [
          dune
          ocaml
        ];
        buildPhase = ''
          runHook preBuild
          mirage configure -f ${mirageDir}/config.ml -t ${target}
          # Move Opam file to root so a recursive search for opam files isn't required.
          # Prefix it so it doesn't interfere with other packages.
          cp ${mirageDir}/mirage/${pname}-${target}.opam mirage-${pname}-${target}.opam
          cat >>mirage-${pname}-${target}.opam <<EOF
          pin-depends: [
            ["bisect_ppx.dev" "git+https://github.com/aantron/bisect_ppx#2d8dffbbfc0c431a37319d4d9a143836c9ec542e"]
          ]
          EOF
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          cp -R . $out
          runHook postInstall
        '';
      };
  };

  # Description: use dune files generated with `configure`
  # to build a unikernel for the given target.
  build = lib.extendMkDerivation {
    constructDrv = stdenv.mkDerivation;
    inherit excludeDrvArgNames;
    extendDrvArgs =
      finalAttrs:
      {
        pname,
        version,
        src,
        target,
        materializedDir,
        mirageDir ? ".",
        query ? { },
        queryArgs ? { },
        monorepoQuery,
        monorepoQueryArgs ? { },
        overrideUnikernel ? finalAttrs: previousAttrs: { },
        ...
      }@args:
      let
        mirageName = "mirage-${pname}-${target}";
        mirageConfIFD = configure (
          args
          // {
            inherit target;
            opamPackages = opam-nix.queryToScope queryArgs ({ mirage = "*"; } // query);
          }
        );
        mirageConf = configure (
          args
          // {
            inherit target;
            opamPackages = packages;
          }
        );
        packagesMaterialized = opam-nix.materializeOpamProject queryArgs mirageName mirageConfIFD query;
        monorepoMaterialized =
          opam-nix.materializeBuildOpamMonorepo monorepoQueryArgs mirageConfIFD
            monorepoQuery;
        monorepo = opam-nix.unmaterializeQueryToMonorepo monorepoQueryArgs (
          materializedDir + "/${target}/monorepo.json"
        );
        packages =
          (opam-nix.materializedDefsToScope {
            sourceMap.${mirageName} = finalAttrs.passthru.mirageConf;
          } (materializedDir + "/${target}/packages.json")).overrideScope
            unikernelOverlay;

        unikernelOverlay = finalOpam: previousOpam: {
          ${mirageName} = previousOpam.${mirageName}.overrideAttrs (
            lib.composeExtensions (finalUnikernel: previousUnikernel: {
              inherit version;
              __intentionallyOverridingVersion = true;

              env =
                previousUnikernel.env or { }
                // lib.optionalAttrs (finalOpam ? "ocaml-solo5") {
                  OCAMLFIND_CONF = finalOpam.ocaml-solo5 + "/lib/findlib.conf";
                };

              buildPhase = ''
                runHook preBuild
                mkdir duniverse
                echo '(vendored_dirs *)' > duniverse/dune
                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (name: path: ''
                    cp -r ${path} duniverse/${lib.toLower name}
                  '') finalAttrs.passthru.monorepo
                )}
                dune build ${mirageDir} --profile release
                runHook postBuild
              '';

              installPhase = ''
                runHook preInstall
                mkdir -p $out/share/mirageos/
                cp -L ${mirageDir}/dist/${pname}* $out/share/mirageos/
                runHook postInstall
              '';

              # Reduce the full closure size by several hundreds MiB
              # since if you're using an unikernel you probably care about this.
              doNixSupport = false;
              stripAllList = previousUnikernel.stripAllList or [ ] ++ [ "share/mirageos" ];
            }) overrideUnikernel
          );
        };
      in
      {
        pname = "${pname}-${target}";
        installPhase = ''
          runHook preInstall
          cp -R --no-preserve=mode ${finalAttrs.passthru.packages.${mirageName}} $out
          ${lib.optionalString
            (
              (stdenv.hostPlatform.isLinux && target == "unix")
              || (stdenv.hostPlatform.isDarwin && target == "macosx")
            )
            ''
              install -Dm755 $out/share/mirageos/${pname} $out/bin/${pname}
              rm -rf $out/share
            ''
          }
          runHook postInstall
        '';
        passthru = {
          materialize = writeShellApplication {
            name = "${pname}-materialize-${target}";
            runtimeInputs = [
              coreutils
              jq
              nix
            ];
            text = ''
              set -x
              materializedDir=$(nix --extra-experimental-features nix-command -L eval \
                -f. ${pname}.${target}.passthru.materializedDir)
              mkdir -p "$materializedDir/${target}/"
              packagesJson=$(nix --extra-experimental-features nix-command -L build \
                --no-link --print-out-paths --allow-import-from-derivation \
                -f. ${pname}.${target}.passthru.packagesMaterialized)
              jq <"$packagesJson" >"$materializedDir/${target}/packages.json"
              monorepoJson=$(nix --extra-experimental-features nix-command -L build \
                --no-link --print-out-paths --allow-import-from-derivation \
                -f. ${pname}.${target}.passthru.monorepoMaterialized)
              jq <"$monorepoJson" >"$materializedDir/${target}/monorepo.json"
            '';
          };
          inherit
            materializedDir
            mirageConf
            mirageConfIFD
            monorepo
            monorepoMaterialized
            packages
            packagesMaterialized
            ;
        };
      };
  };

  # Description: generate a package set to `build` each one of the given `targets`,
  # with an additional `update` package providing a `materializeTargets` script.
  #
  # Usage: the `materializeTargets` script must be called after having updated
  # the given `src` (and possibly `opam-nix`) to generate required materialization files.
  # This update should be done inside a `update.passthru.updateScript`,
  # that can be inserted with a call to `extend` on the resulting package set.
  builds = lib.extendMkDerivation {
    extendDrvArgs =
      finalAttrs:
      {
        pname,
        src,
        version,
        targets ? finalAttrs.targets or possibleTargets,
        ...
      }@args:
      args;
    constructDrv =
      fnOrArgs:
      let
        finalArgs = lib.fix (lib.toFunction fnOrArgs);
      in
      lib.recurseIntoAttrs (
        lib.makeExtensible (
          finalSet:
          lib.genAttrs finalArgs.targets (target: build (finalArgs // { inherit target; }))
          // {
            update =
              (writeText "${finalArgs.pname}-${finalArgs.version}" ''
                This package only exists to provide a location for an `updateScript`
                updating `src` only once before calling `materializeTargets`.
              '').overrideAttrs
                (
                  finalAttrs: _previousAttrs: {
                    # Let `update-source-version` find where to update `version` and `hash`.
                    pos = builtins.unsafeGetAttrPos "src" finalArgs;
                    version = finalArgs.version;
                    passthru = {
                      inherit (finalArgs) src materializedDir targets;
                      materializeTargets = writeShellApplication {
                        name = "${finalArgs.pname}-materializeTargets";
                        text = ''
                          materializedDir=$(nix --extra-experimental-features nix-command -L eval \
                            -f. ${finalArgs.pname}.${lib.head finalArgs.targets}.passthru.materializedDir)
                          rm -f "$materializedDir/*/*.json"
                        ''
                        + lib.concatMapStringsSep "\n" (
                          target: lib.getExe finalSet.${target}.passthru.materialize
                        ) finalArgs.targets;
                      };
                    };
                  }
                );
          }
        )
      );
  };

  possibleTargets = [
    "genode"
    "hvt"
    "macosx"
    "muen"
    "qubes"
    "spt"
    "unix"
    "virtio"
    "xen"
  ];
}
