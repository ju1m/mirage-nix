{
  description = "Mirage Nix packages";
  nixConfig = {
  };
  inputs = {
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
            pkgs = inputs.nixpkgs.legacyPackages.${system};
            treefmt = inputs.treefmt-nix.lib.evalModule pkgs {
              projectRootFile = "flake.nix";
            };
          }
        );
    in
    {
      packages = foreachSystem (
        { ... }: {
        }
      );
      devShells = foreachSystem (
        {
          pkgs,
          haskellPackages,
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
        { system, pkgs, ... }: {
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
      );
      formatter = foreachSystem ({ treefmt, ... }: treefmt.config.build.wrapper);
    };
}
