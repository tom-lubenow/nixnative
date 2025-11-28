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

    # Create temp dir for tracking in-flight jobs
    let pending_dir = (mktemp -d)
    let monitor_script = ($pending_dir | path join "monitor.sh")

    # Write monitor script that prints still-running jobs every 60s
    let running_line = "    running=$(ls '" + $pending_dir + "' 2>/dev/null | grep -v monitor.sh | sort)"
    let script_lines = [
        "#!/bin/bash"
        "while true; do"
        "    sleep 60"
        $running_line
        '    if [ -n "$running" ]; then'
        "        echo ''"
        "        echo '⏳ Still running:'"
        ('        echo "$running" | sed ' + "'" + 's/^/   /' + "'")
        "        echo ''"
        "    fi"
        "done"
    ]
    $script_lines | str join "\n" | save -f $monitor_script
    chmod +x $monitor_script

    # Start monitor in background (use bash to handle backgrounding)
    ^bash -c $"'($monitor_script)' &"
    sleep 100ms  # Give it time to start
    let monitor_pid = (^pgrep -nf "monitor.sh" | str trim | into int | default 0)

    let results = $examples | par-each --threads $jobs { |dir|
        let name = ($dir | path basename)

        # Mark job as in-flight
        touch ($pending_dir | path join $name)

        let start = (date now)

        let nix_args = ["flake" "check" "-j1" "--no-warn-dirty"]
        let nix_args = if $no_build { $nix_args | append "--no-build" } else { $nix_args }

        let result = do { cd $dir; ^nix ...$nix_args } | complete

        let elapsed = ((date now) - $start | into int) / 1_000_000_000
        let success = ($result.exit_code == 0)
        let time = $elapsed | math round --precision 1

        # Print progress immediately (single print to avoid interleaving)
        let status = if $success { $"(ansi green)✓(ansi reset)" } else { $"(ansi red)✗(ansi reset)" }
        let line = $"($status) ($name) \(($time)s\)"
        let output = if $success {
            $line
        } else {
            let indent = $"(char newline)  "
            let errors = $result.stderr | str trim | lines | first 5 | str join $indent
            $"($line)(char newline)  (ansi yellow)($errors)(ansi reset)"
        }
        print $output

        # Mark job as complete
        rm -f ($pending_dir | path join $name)

        {
            name: $name
            success: $success
            elapsed_sec: $elapsed
        }
    }

    # Stop the monitor
    if $monitor_pid > 0 {
        kill $monitor_pid
    }
    rm -rf $pending_dir

    print ""

    let passed = ($results | where success | length)
    let failed = ($results | where { not $in.success } | length)
    let total_time = ($results | get elapsed_sec | math sum | math round --precision 1)

    print $"Summary: ($passed)/($results | length) passed, ($failed) failed \(($total_time)s total\)"

    if $failed > 0 {
        exit 1
    }
}
