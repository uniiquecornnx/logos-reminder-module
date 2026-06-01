{
  description = "Reminders QML UI - frontend for the reminders core module";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/tutorial-v2";
    # Point at the sibling reminders core module by absolute path.
    # (Relative `path:../reminders` fails under pure-eval; absolute works.)
    reminders.url = "path:/Users/devisha/Desktop/logos-reminder-module/reminders";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
