---
name: writing-cli-scripts
description: >
  Uses typer for all Python CLI argument parsing instead of
  argparse. Use whenever creating a Python script that accepts
  command-line arguments, options, or subcommands.
---

# CLI Scripts with Typer

Always use `typer` instead of `argparse` for CLI argument parsing.

## Single command script

```python
import typer
from pathlib import Path


def main(
    input_path: Path,
    output_path: Path = Path("output"),
    verbose: bool = False,
):
    """Process data from input path."""
    ...


if __name__ == "__main__":
    typer.run(main)
```

## Multiple subcommands

```python
import typer

app = typer.Typer()


@app.command()
def train(config: Path, epochs: int = 100):
    """Train the model."""
    ...


@app.command()
def evaluate(checkpoint: Path, split: str = "test"):
    """Evaluate a trained model."""
    ...


if __name__ == "__main__":
    app()
```

## Key rules

- Use Python type hints for all parameters (typer derives CLI types from them).
- Use `Path` for file/directory arguments, not `str`.
- Positional parameters become CLI arguments; parameters with defaults become `--options`.
- Add a docstring to each command function for `--help` text.
- Exception: scripts with no arguments or a single trivial argument may skip typer.
