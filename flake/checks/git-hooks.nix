{
  pkgs,
  inputs,
  system,
  ...
}:
{
  git-hooks = inputs.git-hooks.lib.${system}.run {
    src = ../..;
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
