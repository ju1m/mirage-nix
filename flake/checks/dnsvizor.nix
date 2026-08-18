{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  mkNixOSTest =
    testName: args:
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
        lib.nameValuePair "dnsvizor-${testName}${testArgsToString testArgs}" (
          pkgs.testers.runNixOSTest (
            lib.recursiveUpdate (import ./common.nix) (
              lib.modules.importApply ../../nixos/tests/dnsvizor/dns.nix (
                testArgs
                // {
                  modules = [
                    args.module
                    inputs.self.nixosModules.dnsvizor
                  ];
                }
              )
            )
          )
        );
    in
    lib.listToAttrs (lib.map mkTest (lib.cartesianProduct args.settings));
in
lib.concatMapAttrs mkNixOSTest {
  dns-ipv4 = {
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
    module = ../../nixos/tests/dnsvizor/stub-dns-resolver.nix;
  };
  dns-dualstack = {
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
    module = ../../nixos/tests/dnsvizor/recursive-dns-resolver.nix;
  };
}
