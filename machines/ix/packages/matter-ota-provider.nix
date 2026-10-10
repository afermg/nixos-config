# Build the OTA provider from the very same SDK source/patches as Matter Server.
# No separate release URL, SDK version, binary hash, or absolute store path.
{ lib, chipWheels }:
chipWheels.overrideAttrs (old: {
  pname = "chip-ota-provider-app";

  # Keep nixpkgs' offline build environment and CHIP compatibility patches.
  # Only pre-generate this app, not every SDK example. Serial generation also
  # avoids upstream multiprocessing using all CPUs instead of NIX_BUILD_CORES.
  postPatch = lib.replaceStrings
    [ "scripts/codepregen.py ./zzz_pregenerated/" ]
    [ "scripts/codepregen.py --no-parallel --input-glob '*ota-provider*' ./zzz_pregenerated/" ]
    (old.postPatch or "");

  # Use this SDK release's own OTA application root and args.gni, not its
  # Python-controller settings. These enable e.g. --secured-device-port.
  preConfigure = (old.preConfigure or "") + ''
    cd examples/ota-provider-app/linux
  '';
  gnFlags = lib.filter
    (flag:
      !lib.hasPrefix "chip_project_config_include_dirs=" flag
      && !lib.hasPrefix "chip_python_" flag)
    (old.gnFlags or [ ]) ++ [
      # The server commissions its ephemeral provider over IP, not BLE.
      "chip_config_network_layer_ble=false"
    ];
  ninjaFlags = [ "chip-ota-provider-app" ];
  installPhase = ''
    runHook preInstall
    install -Dm755 chip-ota-provider-app "$out/bin/chip-ota-provider-app"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/chip-ota-provider-app" --help > help.txt
    # Required by Matter Server's ExternalOtaProvider launch contract.
    for flag in passcode discriminator secured-device-port KVS filepath; do
      grep -q -- "--$flag" help.txt
    done
    runHook postInstallCheck
  '';
  meta = old.meta // {
    description = "Matter OTA provider built from the controller's CHIP SDK";
    mainProgram = "chip-ota-provider-app";
    license = lib.licenses.asl20;
  };
})
