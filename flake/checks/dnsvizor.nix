{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  mkNixOSTest =
    testNamePrefix: args:
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
        let
          testName = testArgsToString testArgs;
        in
        lib.nameValuePair "dnsvizor-${testNamePrefix}${testName}" (
          pkgs.testers.runNixOSTest {
            imports = [
              ./common.nix
              (lib.modules.importApply ../../nixos/tests/dnsvizor/dns.nix (
                testArgs // { testName = "DNSVizor-${testName}"; }
              ))
            ];
            extraBaseNodeModules = inputs.self.nixosModules.dnsvizor;
          }
        );
    in
    lib.listToAttrs (lib.map mkTest (lib.cartesianProduct args.settings));
in
lib.concatMapAttrs mkNixOSTest {
  dns = {
    settings = {
      resolverKind = [
        "stub"
        "recursive"
      ];
      useNetworkd = [
        true
        false
      ];
      useNftables = [
        true
        false
      ];
    };
  };
}
