import os
import shlex
import shutil
import subprocess
import sys

TEMPLATE = f"{os.path.dirname(os.path.abspath(__file__))}/template"
COMMANDS_FILE = "commands.txt"
DISPATCH_EXT = (".txt", ".md", ".py", ".sh")


def warn(msg):
    print(f"bd: {msg}", file=sys.stderr)


def confirm(prompt):
    """Ask a [y/N] question; default to No when there's no tty (EOF)."""
    try:
        return input(prompt).strip().lower() == "y"
    except EOFError:
        return False


def run(cmd, shell=False):
    return subprocess.run(cmd, shell=shell, check=False).returncode


def fzf(lines, header="", query=None):
    cmd = ["fzf", "--header", header]
    if query:
        cmd += ["-q", query, "--select-1"]  # auto-accept iff exactly one match
        if not sys.stderr.isatty():
            # No terminal to browse in, so zero matches must not open the UI and block.
            cmd.append("--exit-0")
    proc = subprocess.run(cmd, input="\n".join(lines), text=True, stdout=subprocess.PIPE, check=False)
    if proc.returncode == 2:  # 0 picked, 1 no match, 130 cancelled — 2 is fzf itself failing
        sys.exit(f"bd: fzf failed (exit {proc.returncode})")
    return proc.stdout.strip() or None


def lines_of(path):
    """Non-blank lines of a text file."""
    with open(path, encoding="utf-8") as f:
        return [line for line in f.read().splitlines() if line.strip()]


def list_template_entries(path):
    """Return sorted names in a template directory."""
    return sorted(os.listdir(path))


def view_dir(path):
    """Return non-hidden files and directories in a folder."""
    return [
        entry
        for entry in list_template_entries(path)
        if not entry.startswith(("_", "."))
        and (os.path.isdir(os.path.join(path, entry)) or os.path.isfile(os.path.join(path, entry)))
    ]


def view_commands(template_dir):
    """Return command lines and dispatchable top-level template entries."""
    commands_path = os.path.join(template_dir, COMMANDS_FILE)
    commands = lines_of(commands_path) if os.path.isfile(commands_path) else []
    extra_entries = [
        entry
        for entry in view_dir(template_dir)
        if entry != COMMANDS_FILE
        and (os.path.isdir(os.path.join(template_dir, entry)) or entry.endswith(DISPATCH_EXT))
        and entry not in commands
    ]
    return commands + extra_entries


def menu(template_dir, name):
    """Return command lines or entries for a template folder."""
    path = os.path.join(template_dir, name)
    if os.path.isdir(path):
        return view_dir(path)
    if name == COMMANDS_FILE:
        return view_commands(template_dir)
    return lines_of(path) if os.path.isfile(path) else []


def resolve(template_dir, line):
    """Decide how to run one line: (argv, shell). shell=True means run the raw line.

    The whole dispatch rule lives here, and it touches nothing but the filesystem.
    """
    try:
        first, *args = shlex.split(line)
    except ValueError:
        return line, True  # unbalanced quotes, or nothing to split; let the shell say so
    target = f"{template_dir}/{first}"
    if os.path.isfile(target):
        if first.endswith(".md"):
            return ["less", target], False
        if first.endswith(".py"):
            return [sys.executable, target, *args], False
        if first.endswith(".sh"):
            return ["bash", target, *args], False
    return line, True


def execute(template_dir, line):
    """Run one line: route template files by extension, else hand it to the shell."""
    cmd, shell = resolve(template_dir, line)
    if shell:
        print(line)
    return run(cmd, shell=shell)


def copy_file(template_dir, name):
    source = os.path.join(template_dir, name)
    destination = os.path.join(os.getcwd(), os.path.basename(name))
    if os.path.islink(source) or os.path.islink(destination):
        warn("refusing to copy symlink")
        return 1
    if os.path.lexists(destination):
        if not confirm(f"Overwrite {destination}? [y/N] "):
            return 0
    try:
        shutil.copy2(source, destination)
    except OSError as error:
        warn(f"could not copy {name}: {error}")
        return 1
    print(f"Copied {name} to {destination}")
    return 0


def dispatch(template_dir, query=None):
    name = COMMANDS_FILE
    queries = [query] if isinstance(query, str) else list(query or [])
    while True:
        entries = menu(template_dir, name)
        if not entries:
            warn(f"template/{name} has nothing to run")
            return 1
        selected = fzf(entries, header=f"template/{name}", query=queries[0] if queries else None)
        if not selected:
            return 0
        current_path = os.path.join(template_dir, name)
        if os.path.isdir(current_path):
            selected_path = os.path.join(current_path, selected)
            if os.path.isdir(selected_path):
                queries = queries[1:]
                name = os.path.join(name, selected)
                continue
            if os.path.isfile(selected_path):
                return copy_file(template_dir, os.path.join(name, selected))
            return 1
        try:
            first, *_ = shlex.split(selected)
        except ValueError:
            return execute(template_dir, selected)
        first_path = os.path.join(template_dir, first)
        if os.path.isdir(first_path):
            queries = queries[1:]
            name = first
            continue
        if first.endswith(".txt") and os.path.isfile(first_path):
            queries = queries[1:]
            name = first
            continue
        return execute(template_dir, selected)


def main(template_dir=TEMPLATE):
    if not shutil.which("fzf"):
        hint = "brew install fzf" if sys.platform == "darwin" else "see https://github.com/junegunn/fzf#installation"
        sys.exit(f"bd: fzf not found. Install: {hint}")
    args = sys.argv[1:]
    sys.exit(dispatch(template_dir, query=args))


if __name__ == "__main__":
    main()
