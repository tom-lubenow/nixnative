#!/usr/bin/env nu

# Parallel flake check for all nixnative examples
# Runs `nix flake check` in each example directory with 1 CPU per check

def main [
    --jobs (-j): int  # Number of parallel jobs (default: number of CPUs)
    --no-build        # Skip building, only check evaluation
] {
    let num_cpus = (sys cpu | length)
    let jobs = if $jobs != null { $jobs } else { $num_cpus }

    print $"Running flake checks with ($jobs) parallel jobs \(($num_cpus) CPUs detected\)"

    # Find all example directories with flake.nix
    let examples = (glob "examples/*/flake.nix"
        | each { path dirname }
        | sort
    )

    print $"Found ($examples | length) examples to check"
    print ""

    let results = $examples | par-each --threads $jobs { |dir|
        let name = ($dir | path basename)
        let start = (date now)

        let nix_args = ["flake" "check" "-j1" "--no-warn-dirty"]
        let nix_args = if $no_build { $nix_args | append "--no-build" } else { $nix_args }

        let result = do { cd $dir; ^nix ...$nix_args } | complete

        let elapsed = ((date now) - $start | into int) / 1_000_000_000

        {
            name: $name
            success: ($result.exit_code == 0)
            exit_code: $result.exit_code
            elapsed_sec: $elapsed
            stderr: $result.stderr
        }
    }

    # Sort results by name for consistent output
    let results = $results | sort-by name

    print "Results:"
    print "--------"

    for r in $results {
        let status = if $r.success { $"(ansi green)✓(ansi reset)" } else { $"(ansi red)✗(ansi reset)" }
        let time = $r.elapsed_sec | math round --precision 1
        print $"($status) ($r.name) \(($time)s\)"

        if not $r.success {
            let indent = $"  (char newline)  "
            print $"  (ansi yellow)($r.stderr | str trim | lines | first 5 | str join $indent)(ansi reset)"
        }
    }

    print ""

    let passed = ($results | where success | length)
    let failed = ($results | where { not $in.success } | length)
    let total_time = ($results | get elapsed_sec | math sum | math round --precision 1)

    print $"Summary: ($passed)/($results | length) passed, ($failed) failed \(($total_time)s total\)"

    if $failed > 0 {
        exit 1
    }
}
