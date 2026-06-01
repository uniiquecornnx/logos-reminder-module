{
  description = "Reminders module - local sticky reminders for Logos basecamp";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/tutorial-v2";

    # The C library source, built from source by Nix (see metadata.json's
    # external_libraries). flake = false means "just give me the source tree".
    reminders-src = {
      url = "path:./lib";
      flake = false;
    };
  };

  outputs = inputs@{ logos-module-builder, reminders-src, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;

      # Hand the C source to the builder. The attribute name (reminders) must
      # match the external_libraries[].name in metadata.json.
      externalLibInputs = {
        reminders = reminders-src;
      };
    };
}
