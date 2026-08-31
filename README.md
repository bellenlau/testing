# Quantum ESPRESSO Testing

`qe-suite/launch.sh` reuses Quantum ESPRESSO when available or builds it,
prepares the upstream test suite, and can submit it to Slurm on Leonardo.

All generated files are stored below `work/`; no build or test artifact is
written below `$HOME`.

## Files

- `qe-suite/launch.sh`: main command. It selects a version and stack, finds or
	builds `pw.x`, stages a new run, and prepares the required pseudopotentials.
- `qe-suite/lib/build.sh`: clones the selected QE release, configures it with
	CMake, builds it, and installs it below `work/builds/`.
- `qe-suite/lib/collect-results.sh`: waits for Slurm accounting and creates JSON
	and JUnit reports.
- `qe-suite/submit.sh`: Slurm job that loads the stack and runs all configured
	QE test categories.
- `qe-suite/stacks/dcgp.env`: CPU/DCGP software and Slurm profile.
- `qe-suite/stacks/booster.env`: GPU/Booster software and Slurm profile.

Each stack profile defines modules, CMake options, launcher behavior, and Slurm
resources. Adapt account, partition, QoS, and modules to the available Leonardo
configuration when necessary.

## Manual Usage

Prepare QE 7.6 and its test suite on DCGP without submitting a job:

```bash
cd /leonardo_scratch/large/userinternal/lbellen1/vscode/testing/qe-suite
./launch.sh --version 7.6 --stack-file stacks/dcgp.env
```

Prepare and submit the complete suite on Booster:

```bash
./launch.sh --version 7.6 --stack-file stacks/booster.env --submit
```

Use `--wait` instead of `--submit` to wait for the terminal Slurm state and
generate `summary.json` and `junit.xml`. Use `--force-rebuild` to run CMake,
`make -j`, and installation again instead of reusing a matching local build.

The launcher reuses `pw.x` only if its reported version matches `--version`.
Otherwise, it clones tag `qe-VERSION` and installs it below `work/builds/`.
Sources are kept under `work/sources/`.

Each run is stored under `work/runs/` and contains the staged `test-suite`,
pseudopotentials, per-category `test_out_*.log` files, `job.id`,
`categories.status`, and Slurm output. During preparation, the launcher runs
`make pseudo` in the staged test suite. This command must succeed before a job
can be submitted.

## GitLab CI

The repository remains usable both manually and through GitLab CI on the Cineca
GitLab instance. The pipeline calls the same `qe-suite/launch.sh` command and
does not maintain a separate build or test implementation.

Pipelines run for tags and can also be started manually from GitLab with these
variables:

- `QE_VERSION`: QE release used when the tag does not specify one.
- `STACKS`: `dcgp`, `booster`, or `all`.
- `FORCE_REBUILD`: `true` or `false`.
- `QE_WAIT_TIMEOUT`: maximum time in seconds spent waiting for Slurm accounting.

A tag named `qe-vX.Y` selects QE version `X.Y`; other tags use `QE_VERSION`.

The project requires a protected self-hosted GitLab Runner tagged
`leonardo-login` on a Leonardo login node. Its `builds_dir` must be below
`/leonardo_scratch`, not `$HOME`. The runner needs access to `module`, `git`,
`make`, `jq`, `xmllint`, `sbatch`, `sacct`, the selected partitions, and the
required Slurm account. Restrict the runner to trusted refs.

Every CI job publishes `summary.json`, JUnit XML, `categories.status`, test
logs, the generated batch script, and Slurm output as artifacts for 14 days,
including when the regression job fails.
