# QE Test Suite

This directory builds or reuses Quantum ESPRESSO and runs its full upstream test suite on Leonardo.

## Contents

- `launch.sh`: main command; builds, stages, and optionally submits tests.
- `lib/build.sh`: CMake configuration, `make -j`, and installation.
- `submit.sh`: Slurm job that runs all QE test categories.
- `stacks/`: software-stack profiles for Booster and DCGP.
- `WORKFLOW_*.txt`: short platform-specific command references.

Generated sources, builds, logs, and test runs are stored below `../work/`.

## Usage

Prepare QE 7.6 and the test suite on Booster:

```bash
./launch.sh --version 7.6 --stack-file stacks/booster.env
```

Prepare QE 7.6 and the test suite on DCGP:

```bash
./launch.sh --version 7.6 --stack-file stacks/dcgp.env
```

Submit the complete suite to Slurm:

```bash
./launch.sh --version 7.6 --stack-file stacks/booster.env --submit
```

Add `--wait` to wait for the job. A completed local build is reused automatically. Use `--force-rebuild` to run CMake, `make -j`, and installation again.
