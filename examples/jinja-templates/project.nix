{ pkgs, native }:

let
  # Configuration variables
  configVars = {
    appName = "jinja-example";
    version = "1.2.3";
    versionMajor = 1;
    versionMinor = 2;
    versionPatch = 3;
    debug = true;
    maxConnections = 100;
    bufferSize = 4096;
  };

  messageVars = {
    messages = [
      { name = "WELCOME"; text = "Welcome to the application!"; description = "Shown on startup"; }
      { name = "GOODBYE"; text = "Thank you for using jinja-example!"; description = "Shown on exit"; }
      { name = "ERROR_MSG"; text = "An error has occurred."; description = "Generic error"; }
    ];
  };

  # Generate code from template files
  templatesGen = native.tools.jinja.run {
    inputFiles = [
      "templates/config.h.j2"
      "templates/messages.h.j2"
      "templates/messages.cc.j2"
    ];
    root = ./.;
    config = {
      variables = configVars // messageVars;
      templates = [
        { template = "templates/config.h.j2"; output = "config.h"; variables = configVars; }
        { template = "templates/messages.h.j2"; output = "messages.h"; variables = messageVars; }
        { template = "templates/messages.cc.j2"; output = "messages.cc"; variables = messageVars; }
      ];
    };
  };

  # Enum generator
  statusEnum = native.tools.enumGenerator {
    name = "Status";
    namespace = "app";
    values = [ "IDLE" "RUNNING" "PAUSED" "STOPPED" ];
  };

  # Build app
  app = native.executable {
    name = "jinja-example";
    root = ./.;
    sources = [ "main.cc" ];
    tools = [ templatesGen statusEnum ];
  };

in {
  inherit app;
  jinjaTemplatesExample = app;
}
