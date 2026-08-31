# Quantum ESPRESSO Testing

`qe-suite/launch.sh` riusa Quantum ESPRESSO quando disponibile oppure la
compila, prepara la test suite upstream e puo sottometterla a Slurm.

All generated files are below `testing/work`; no build or test artifact is
written below `$HOME`.

## File

- `qe-suite/launch.sh`: comando principale. Riceve versione e profilo, cerca
	`pw.x`, compila QE se non trova la versione richiesta, prepara una nuova run
	e scarica i pseudopotenziali richiesti dalla test suite.
- `qe-suite/lib/build.sh`: esegue clone, configurazione CMake, build e install.
	E separato dal launcher solo per mantenere leggibile il flusso principale.
- `qe-suite/submit.sh`: job Slurm. Carica lo stack, configura l'ambiente della
	test suite e avvia tutte le categorie QE.
- `qe-suite/stacks/dcgp.env`: esempio di profilo CPU/DCGP.
- `qe-suite/stacks/booster.env`: esempio di profilo GPU/Booster.

Ogni profilo dichiara moduli, opzioni `configure` e risorse Slurm. I valori
devono essere adattati ai moduli e all'account disponibili sul sistema.

## Profili stack

Un profilo e un file shell controllato dal repository. Definisce i moduli da
caricare, le opzioni CMake e le risorse Slurm. Gli esempi sono
`qe-suite/stacks/dcgp.env` e `qe-suite/stacks/booster.env`. Adatta nomi dei
moduli, partition e, se necessario, `SLURM_ACCOUNT`.

## Usage

Prepare QE 7.6 and its test suite using the CPU profile:

```bash
cd /leonardo_scratch/large/userinternal/lbellen1/vscode/testing/qe-suite
./launch.sh --version 7.6 --stack-file stacks/dcgp.env
```

Usa `--submit` per sottomettere la run. Usa `--wait` per attendere il job e
stampare lo stato di ogni categoria.

The script reuses `pw.x` only if its reported QE version matches `--version`.
Otherwise it clones tag `qe-VERSION`, builds and installs it beneath
`testing/work/builds/`. The corresponding source checkout and test suite are
kept under `testing/work/sources/`.

Each suite run is placed in `testing/work/runs/`. It contains the staged
`test-suite`, pseudopotentials, log `test_out_*.log` per categoria, job ID e
`categories.status`. During preparation, the launcher runs `make pseudo` in the
staged `test-suite`; it must complete successfully before `--submit` invokes
`sbatch`. Una categoria fallita fa terminare il job Slurm con codice nonzero,
quindi una CI puo usare direttamente lo stato del job.