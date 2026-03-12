# GitHub Actions build for MT4

This workflow compiles `TradeAction.mq4` into `TradeAction.ex4` on a self-hosted Windows runner that already has MetaTrader 4 / MetaEditor installed. It writes the MetaEditor compile output to `metaeditor-mt4-compile.log`, fails the job when compilation fails or when `TradeAction.ex4` is not produced, and uploads the `.ex4` file plus the compile log as workflow artifacts.

## Files

- Workflow: `.github/workflows/build-mt4.yml`
- Source file: `TradeAction.mq4`
- Build output: `TradeAction.ex4`
- Compile log: `metaeditor-mt4-compile.log`

## Why this workflow uses a self-hosted Windows runner

MetaEditor is a Windows desktop application that is typically installed together with a local MetaTrader 4 terminal. GitHub-hosted runners do not come with MT4 or MetaEditor preinstalled, and installing or maintaining that stack during every workflow run is brittle. A self-hosted Windows runner gives you a fixed MetaEditor path, a stable MT4 installation, and predictable compile behavior.

## Configure the self-hosted Windows runner

1. Prepare a Windows machine that has MetaTrader 4 and `metaeditor.exe` installed.
2. In GitHub, open `Settings -> Actions -> Runners` for this repository.
3. Add a new self-hosted runner for Windows and complete the setup steps on that machine.
4. Add a custom runner label such as `mt4` so the workflow targets only the machine that has MetaEditor installed.
5. Make sure the runner account can read the repo workspace and launch `metaeditor.exe`.

Recommended labels for this workflow:

- `self-hosted`
- `Windows`
- `X64`
- `mt4`

If your runner uses different labels, update `runs-on` in `.github/workflows/build-mt4.yml`.

## Set `METAEDITOR_PATH`

The workflow resolves MetaEditor in this order:

1. Repository variable `METAEDITOR_PATH`
2. Environment variable `METAEDITOR_PATH` on the self-hosted runner

Recommended setup is a repository variable:

1. Open `Settings -> Secrets and variables -> Actions -> Variables`.
2. Create a variable named `METAEDITOR_PATH`.
3. Set it to the full path of MetaEditor, for example:

```text
C:\Program Files (x86)\MetaTrader 4\metaeditor.exe
```

You can also set `METAEDITOR_PATH` directly in the Windows environment for the runner service account.

## Triggering the workflow

The workflow runs on:

- `push` to `main`
- every `pull_request`
- manual start through `workflow_dispatch`

## View build artifacts

1. Open the repository `Actions` tab.
2. Open a specific workflow run named `Build MT4 EA`.
3. In the run summary, open the `Artifacts` section.
4. Download `mt4-build` to get:

- `TradeAction.ex4`
- `metaeditor-mt4-compile.log`

## Common issues

### No runner matched the requested labels

The self-hosted runner does not have the labels listed in `runs-on`. Add the `mt4` label to the runner or adjust the workflow labels.

### `METAEDITOR_PATH` is not set

Create the repository variable `METAEDITOR_PATH`, or define the same environment variable on the self-hosted runner.

### MetaEditor not found at the configured path

Double-check the exact path to `metaeditor.exe` on the runner machine. Paths under `Program Files` often differ between terminals or broker-branded MT4 installs.

### Compile log exists but the job still fails

Read `metaeditor-mt4-compile.log` from the artifact. The workflow fails when MetaEditor exits with a non-zero code, reports compile errors in the log, or does not generate `TradeAction.ex4`.

### `TradeAction.ex4` was not created

The compile step removes any stale `.ex4` before running MetaEditor. If the new file is still missing, the compile did not finish successfully or MetaEditor is compiling a different path than expected. Check the source path and the log content first.

### MetaEditor starts locally but fails in GitHub Actions

Some runner service accounts cannot launch desktop applications correctly. If that happens, run the Windows self-hosted runner under an account that can open MetaEditor, or run the runner interactively on the MT4 machine.
