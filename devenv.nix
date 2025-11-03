{ pkgs, lib, config, inputs, ... }:

{

  packages = [ pkgs.git ];

  languages.ruby.enable = true;
  languages.ruby.version = "3.4.7";

}
