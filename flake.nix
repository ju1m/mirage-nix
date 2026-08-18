{
  description = "MirageOS Nix packages";
  nixConfig = {
  };
  inputs = {
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mirage-opam-overlays = {
      url = "github:dune-universe/mirage-opam-overlays";
      flake = false;
    };
    nixpkgs.url = "flake:nixpkgs";
    opam-nix = {
      url = "github:tweag/opam-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.opam-repository.follows = "opam-repository";
      inputs.opam-overlays.follows = "opam-overlays";
      inputs.mirage-opam-overlays.follows = "mirage-opam-overlays";
    };
    opam-overlays = {
      url = "github:dune-universe/opam-overlays";
      flake = false;
    };
    opam-repository = {
      url = "github:ocaml/opam-repository";
      flake = false;
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    inputs:
    let
      lib = inputs.nixpkgs.lib;
      fileInputs =
        with lib.fileset;
        toSource {
          root = ./.;
          fileset = unions [
          ];
        };
      foreachSystem =
        f:
        lib.genAttrs lib.systems.flakeExposed (
          system:
          f rec {
            inherit system;
            pkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [
                inputs.self.overlays.default
              ];
            };
            treefmt = inputs.treefmt-nix.lib.evalModule pkgs {
              projectRootFile = "flake.nix";
            };
          }
        );
    in
    {
      packages = foreachSystem (
        { pkgs, ... }: {
          dnsvizor = pkgs.callPackage pkgs/by-name/dnsvizor/package.nix { };
        }
      );
      overlays.default =
        finalPkgs: previousPkgs:
        {
          mirage = finalPkgs.callPackage lib/mirage.nix { };
          opam-nix = inputs.opam-nix.lib.${finalPkgs.stdenv.hostPlatform.system};
        }
        // inputs.self.packages.${previousPkgs.stdenv.hostPlatform.system};
      nixosModules = {
        dnsvizor = nixos/modules/services/dnsvizor.nix;
      };
      devShells = foreachSystem (
        {
          pkgs,
          system,
          ...
        }:
        {
          default = pkgs.mkShell {
            inherit (inputs.self.checks.${system}.git-hooks-check) shellHook;
          };
        }
      );
      checks = foreachSystem (
        { system, pkgs, ... }:
        {
          git-hooks-check = inputs.git-hooks.lib.${system}.run {
            src = ./.;
            package = pkgs.prek;
            default_stages = [
              "manual"
              "pre-push"
            ];
            hooks = {
              nixfmt.enable = true;
            };
          };
        }
        // (
          let
            mkNixOSTest =
              args:
              lib.nameValuePair args.testName (
                let
                  testArgToString =
                    name: param: sep:
                    if param == true then
                      "-" + name
                    else if param == false then
                      ""
                    else if lib.isString param then
                      "-" + param
                    else
                      throw "testArgToString: not implemented for ${name}=${toString param}";
                  testArgsToString =
                    testArgs:
                    lib.pipe testArgs [
                      (lib.mapAttrs (name: param: testArgToString name param "-"))
                      lib.attrValues
                      lib.concatStrings
                    ];
                  mkTest =
                    testArgs:
                    lib.nameValuePair "dnsvizor-${args.testName}${testArgsToString testArgs}" (
                      pkgs.testers.runNixOSTest (
                        lib.modules.importApply nixos/tests/dnsvizor/dns.nix (
                          testArgs
                          // {
                            modules = [
                              args.module
                              inputs.self.nixosModules.dnsvizor
                            ];
                          }
                        )
                      )
                    );
                in
                lib.listToAttrs (lib.map mkTest (lib.cartesianProduct args.settings))
              );
          in
          lib.listToAttrs (
            map mkNixOSTest [
              {
                testName = "dns-ipv4";
                settings = {
                  resolverKind = [ "stub" ];
                  useNetworkd = [
                    true
                    false
                  ];
                  useNftables = [
                    true
                    false
                  ];
                };
                module = nixos/tests/dnsvizor/stub-dns-resolver.nix;
              }
              {
                testName = "dns-dualstack";
                settings = {
                  resolverKind = [ "recursive" ];
                  useNetworkd = [
                    true
                    false
                  ];
                  useNftables = [
                    true
                    false
                  ];
                };
                module = nixos/tests/dnsvizor/recursive-dns-resolver.nix;
              }
            ]
          )
        )
      );
      formatter = foreachSystem ({ treefmt, ... }: treefmt.config.build.wrapper);
    };
}
