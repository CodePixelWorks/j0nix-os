{ lib, pkgs, settings, ... }:
let
  gaming = settings.gaming or { };
  enabled = gaming.enable or true;
  controllerCfg = gaming.controllers or { };
  controllerEnabled = controllerCfg.enable or true;
in
lib.mkIf (enabled && controllerEnabled) {
  boot.kernelModules =
    lib.optionals (controllerCfg.nintendo or true) [ "hid_nintendo" ]
    ++ lib.optionals (controllerCfg.xbox or true) [ "xpad" ]
    ++ [ "uinput" ];

  boot.kernelParams = lib.optionals (controllerCfg.nintendo or true) [
    "usbhid.quirks=0x057e:0x2009:0x80000000"
  ];

  hardware = {
    steam-hardware.enable = true;
    xpadneo.enable = controllerCfg.xbox or true;
  };

  services.udev.extraRules = lib.mkAfter ''
    # Nintendo Switch Pro Controller over USB
    KERNEL=="hidraw*", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2009", MODE="0666", TAG+="uaccess"

    # Nintendo Switch Pro Controller over Bluetooth
    KERNEL=="hidraw*", KERNELS=="*057E:2009*", MODE="0666", TAG+="uaccess"

    # Xbox One Controller over USB
    KERNEL=="hidraw*", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="02ea", MODE="0666", TAG+="uaccess"
    KERNEL=="hidraw*", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="02dd", MODE="0666", TAG+="uaccess"

    # Xbox Series X|S Controller
    KERNEL=="hidraw*", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="0b20", MODE="0666", TAG+="uaccess"

    # Disable DualSense touchpad as mouse
    ACTION=="add|change" ATTRS{name}=="Sony Interactive Entertainment DualSense Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
    ACTION=="add|change" ATTRS{name}=="DualSense Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"

    # Generic fallback for controllers
    SUBSYSTEM=="input", ATTRS{name}=="*Controller*", MODE="0666", TAG+="uaccess"
    SUBSYSTEM=="input", ATTRS{name}=="*Gamepad*", MODE="0666", TAG+="uaccess"
  '';

  environment.systemPackages = with pkgs; [
    SDL2
    jstest-gtk
    evtest
    antimicrox
  ];
}
