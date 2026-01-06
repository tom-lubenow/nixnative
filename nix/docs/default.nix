# Documentation generator entry point
#
# Usage:
#   nix build .#docs-generated
#
# Produces a derivation with generated markdown files in api/
{ pkgs, lib ? pkgs.lib }:

let
  generator = import ./generate.nix { inherit lib; };
  docs = generator.generateDocs;

in
pkgs.runCommand "nixnative-docs-generated" { } ''
  mkdir -p $out/api

  cat > $out/api/index.md << 'EOF'
  ${docs.index}
  EOF

  cat > $out/api/project.md << 'EOF'
  ${docs.project}
  EOF

  cat > $out/api/targets.md << 'EOF'
  ${docs.targets}
  EOF

  cat > $out/api/defaults.md << 'EOF'
  ${docs.defaults}
  EOF

  cat > $out/api/tests.md << 'EOF'
  ${docs.tests}
  EOF

  cat > $out/api/shells.md << 'EOF'
  ${docs.shells}
  EOF
''
