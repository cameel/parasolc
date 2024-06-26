# parasolc

Proof of concept of parallelizing the [Solidity compiler](https://github.com/ethereum/solidity/) via multiprocessing.

`parasolc.sh` is a drop-in replacement for `solc`, providing a small subset of its command-line interface.
The script works by splitting the received Standard JSON input into a set of smaller compilation tasks
for `solc`, executing them all in parallel and merging the results into a single Standard JSON output.

## Status

Unfortunately, as of `solc` 0.8.26, the usefulness of this method of parallelization is limited.
The amount of extra processing needed is very large (several times the original work), which
negates a lot of the gain.
It is not useless - a machine with multiple cores still comes out ahead in terms of compilation time -
but it is a trade-off, not an universal improvement.

The full report is available here: [The parasolc experiment](https://notes.ethereum.org/@solidity/parasolc-experiment).

## How it works

### Split methods
Currently the script supports two methods of dividing the work:

- `naive`: The simplest way to perform parallel compilation: include all sources in the `sources` array and
    use `settings.outputSelection` to request compilation of one contract at a time.

    This relies on the fact that `solc` performs only as much work as necessary to generate the requested outputs.
    If a contract is not selected, its source file is still analyzed, but code generation is skipped.

- `clustered`: This method clusters together contracts which depend on each other's bytecode to avoid
    compiling the same contract multiple times.
    One Standard JSON input per cluster is generated.

    Deploying a contract at runtime using `new` or using `.runtimeCode`/`.creationCode` requires access to the bytecode of that contract at runtime.
    This forces the bytecode of the contract being accessed to be included as a subassembly in the bytecode of the accessing contract.
    `solc` detects such dependencies and reuses already compiled bytecode.
    This is not possible if the contracts are being compiled independently.
    Clustering removes the unnecessary work at the cost of forcing the contracts to be compiled sequentially.

    The information about these dependencies is available on the `ContractDefinition` node in the AST (`.contractDependencies`).
    Based on it, one can build a graph of bytecode dependencies.
    Each connected component of the graph represents a cluster that is best compiled together for maximum bytecode reuse.

### Stripping unused sources
Since each source has to be analyzed by the compiler, providing files that are not relevant to the requested output is pure overhead.
The script can optionally remove them, which should generally speed up the compilation.

The downside of this is that the set of the input contracts may affect produced artifacts.
The compiler tries hard to guarantee that the generated bytecode stays the same but this is
not necessarily true for aritfacts which are only meant as a debugging aid.
Also, historically, this guarantee has been hard to uphold and affected by many bugs.
Including all sources in all parallel tasks vastly reduces the chances of running into one of them
by ensuring that the parser will generate the same AST IDs.
Code generation not being independent of AST IDs is the most common source of such bugs.

One example of such an artifact are the source maps, which refer to source files by IDs.
The IDs are sequential and may be different for a different set of input files.
To match the output of non-parallelized compilation, the IDs must be translated when merging the outputs.

A more problematic example are artifacts that contain IDs and names based on the AST IDs.
For example IDs and names included in `functionDebugData` and `immutableReferences` may change.
These may be impossible to translate.

Finally, note that stripping unused sources is only a partial solution, as it cannot completely
eliminate the need to analyze files multiple times.
Any imported sources will necessarily be present in more than one compilation task and analyzed
independently in each of them.

## Settings

There following settings can be adjusted via environment variables:
- `SOLC_BINARY`: Path to the compiler binary to use.
    Defaults to a `solc` executable stored in the same directory as the script.
- `SPLIT_METHOD` (`naive`, `clustered`): How to divide the input into smaller tasks.
    Default: `naive`.

    Note that `clustered` requires a custom build of the compiler (see below).
- `ONLY_RELEVANT_SOURCES` (`true`, `false`): Whether the mechanism stripping unused sources should be used.
    Default: `false`.

Usage example with all the options:
```bash
SOLC_BINARY=solc \
SPLIT_METHOD=naive \
ONLY_RELEVANT_SOURCES=true \
./parasolc.sh \
    --standard-json - \
    --base-path contracts/openzeppelin-contracts/ \
    < test/oz-erc20.json
```

## Usage with Foundry
The script is designed to work with `forge --use`:
```bash
forge build --use "<parasolc repo path>/parasolc.sh"
```

Here's a more complex example that can be used to quickly benchmark parallelization with a Foundry-based project.
It also shows how to pass in extra options:

```bash
SOLC_BINARY=solc \
forge build \
    --use "<parasolc repo path>/parasolc.sh" \
    --optimize \
    --via-ir \
    --evm-version cancun \
    --offline \
    --no-cache
```

**Warning**: The script is not meant for production use.
See the section about limitations.

## Dependencies
The script is written in Bash, using only simple shell utilities, most notably:
- [`jq`](https://jqlang.github.io/jq/)
- GNU `xargs`

For building, testing and benchmarking the following may be needed as well:
- [Foundry](https://github.com/foundry-rs/foundry)
- GNU `make`
- git
- any dependencies necessary to build `solc` (`cmake`, `Boost`, etc.)

### Custom `solc` with `compilerHints` output

The repository includes a patch for the Solidity compiler that adds an extra output called `compilerHints`.
Currently the output provides information on how the contracts should be grouped together to maximize
the bytecode reuse.
The script depends on this output when the `clustered` method is selected.

To build the compiler simply run:
```bash
make solc
```

By default build is performed in the script directory.
This can be changed via the `OUTPUT_DIR` variable:
```bash
make solc OUTPUT_DIR=/tmp/parasolc
```

## Benchmarking
The `test/` directory contains sample Standard JSON input based on several popular projects and
a script that can download them and run a basic benchmark, comparing the execution time of
`solc` and `parasolc`.
You can run it with:
```bash
make benchmark
```

The benchmarking script also compares the output from both methods.
Since the script is not sophisticated enough to merge the output perfectly in all cases,
a comparison of only bytecode is performed as well.

The target accepts two variables:
- `OUTPUT_DIR`: The location to store downloaded sources and results of compilation.
    The script directory is used by default.
- `SOLC_BINARY`: Path to the compiler binary to use.
    Defaults to a `solc` executable stored in the `OUTPUT_DIR`.

## Limitations and known issues
1. The following `solc` bug may prevent parallel compilation when circular dependencies are present:
    [Error: `Definition of base has to precede definition of derived contract` when specific file in standard-json-input `outputSelection` but works when `outputSelection` file is specific](https://github.com/ethereum/solidity/issues/12932).
    This currently affects Uniswap v4, which is one of the contracts used for benchmarking.
    Until the bug is fixed, this method requires careful ordering of the input files to avoid running
    into it (the script does not do this).
1. The following `solc` bug results in different bytecode for some of OpenZeppelin's test contracts in parallel compilation:
    [Different bytecode produced via IR for some of OpenZeppelin's contracts when extra contracts are included in the input #15134](https://github.com/ethereum/solidity/issues/15134)
1. The output merging is very basic and cannot deal with some more complex situations.
    In particular, errors emitted at the code generation stage are not always in the same order that
    solc uses and duplicates are not always correctly removed.
1. The ID translation necessary to get merged output identical with solc when using
    `ONLY_RELEVANT_SOURCES=true` is not implemented.
1. As already mentioned above, this method of parallelization has a very high overhead, probably coming from repeated analysis.
    The problem will ultimately need to be addressed in the compiler.
1. The `clustered` method is not a true solution to bytecode dependencies, only a workaround.
    A proper solution will require a compiler mechanism to reuse separately compiled bytecode.
