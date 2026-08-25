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
      inherit (inputs.nixpkgs) lib;
      foreachSystem =
        mk:
        lib.genAttrs lib.systems.flakeExposed (
          system:
          mk rec {
            inherit lib system inputs;
            pkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [
                inputs.self.overlays.default
              ];
            };
            treefmt = inputs.treefmt-nix.lib.evalModule pkgs {
              projectRootFile = "flake.nix";
            };
            unikernelPkgs = lib.mapAttrs (pkgName: pkgFile: pkgs.callPackage pkgFile { }) {
              dnsvizor = pkgs/by-name/dnsvizor/package.nix;
            };
          }
        );
    in
    {
      packages = foreachSystem (
        { pkgs, unikernelPkgs, ... }:
        lib.concatMapAttrs (
          pkgName: pkgFile:
          # Explanation(compatibility): `flake.nix` does not allow nested `packages`
          # hence add a single `dnsvizor` package containing them,
          # and `dnsvizor.${target}` aliases for `nix flake show`.
          {
            ${pkgName} =
              pkgs.emptyDirectory
              // lib.genAttrs unikernelPkgs.${pkgName}.update.targets (
                target: unikernelPkgs.${pkgName}.${target}
              );
          }
          # Description: those are said aliases for `nix flake show`.
          // lib.genAttrs' unikernelPkgs.${pkgName}.update.targets (
            target: lib.nameValuePair "${pkgName}.${target}" unikernelPkgs.${pkgName}.${target}
          )
        ) unikernelPkgs
      );
      overlays.default = final: previous: {
        mirage = final.callPackage lib/mirage.nix { };
        opam-nix = inputs.opam-nix.lib.${final.stdenv.hostPlatform.system};
        inherit (inputs.self.packages.${previous.stdenv.hostPlatform.system})
          dnsvizor
          ;
      };
      nixosModules = {
        dnsvizor = nixos/modules/services/dnsvizor.nix;
      };
      devShells = foreachSystem (
        { pkgs, system, ... }:
        {
          default = pkgs.mkShell {
            inherit (inputs.self.checks.${system}.git-hooks) shellHook;
          };
        }
      );
      checks = foreachSystem (
        { system, pkgs, ... }@args:
        lib.concatMapAttrs (_name: file: import file args) {
          git-hooks = flake/checks/git-hooks.nix;
          dnsvizor = flake/checks/dnsvizor.nix;
        }
      );
      formatter = foreachSystem ({ treefmt, ... }: treefmt.config.build.wrapper);
    };
}
