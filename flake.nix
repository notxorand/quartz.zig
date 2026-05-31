{
  description = "quartz.zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      zig-overlay,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ zig-overlay.overlays.default ];
        };
        commonBuildInputs = with pkgs; [
          zigpkgs."0.16.0"
        ];

      in
      {
        devShells = {
          default = pkgs.mkShell {
            buildInputs = commonBuildInputs;
          };

          lsp = pkgs.mkShell {
            buildInputs =
              with pkgs;
              [
                zls
              ]
              ++ commonBuildInputs;
          };
        };
      }
    );
}
