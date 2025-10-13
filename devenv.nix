{ pkgs, lib, config, inputs, ... }:

{

  packages = [ pkgs.git ];

  languages.ruby = {
    enable = true;
    version = "3.3";
  };

}
