"""Focused tests for template dispatch and file copying."""

import shutil

import pytest

import bd as bd_package
from bd import bd

MISSING = [tool for tool in ("bash",) if not shutil.which(tool)]
pytestmark = pytest.mark.skipif(bool(MISSING), reason=f"bd requires {', '.join(MISSING)}")


def make_template(tmp_path, commands=""):
    template = tmp_path / "template"
    template.mkdir()
    (template / "commands.txt").write_text(commands)
    return template


def test_dispatch_uses_template_without_creating_bd(tmp_path, monkeypatch):
    template = make_template(tmp_path, "echo READY\n")
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(bd, "fzf", lambda lines, header="", query=None: "echo READY")

    assert bd.dispatch(str(template)) == 0
    assert not (tmp_path / ".bd").exists()


def test_commands_run_from_invocation_directory(tmp_path, monkeypatch, capfd):
    template = make_template(tmp_path)
    monkeypatch.chdir(tmp_path)

    assert bd.execute(str(template), "pwd") == 0
    assert capfd.readouterr().out.splitlines()[-1] == str(tmp_path)


def test_view_menu_replaces_text(monkeypatch):
    presented = []
    executed = []

    def fake_fzf(lines, header="", query=None):
        presented.extend(lines)
        assert header == "Example"
        return lines[-1]

    monkeypatch.setattr(bd, "fzf", fake_fzf)
    monkeypatch.setattr(bd, "execute", lambda template_dir, line: executed.append(line) or 3)

    result = bd_package.view_menu(
        """
command1
command2
command3 foo foo
""",
    replace={"foo": "bar"},
        header="Example",
    )

    assert result == 3
    assert presented == ["command1", "command2", "command3 bar bar"]
    assert executed == ["command3 bar bar"]


def test_view_menu_accepts_readlines_and_cancellation(monkeypatch):
    presented = []
    monkeypatch.setattr(bd, "fzf", lambda lines, header="", query=None: presented.extend(lines))
    monkeypatch.setattr(bd, "execute", lambda template_dir, line: pytest.fail("cancelled menu should not execute"))

    assert bd_package.view_menu(["echo foo\n", "\n"], replace={"foo": "bar"}) == 0
    assert presented == ["echo bar"]


def test_tabbed_lines_are_run_as_shell_commands(tmp_path, monkeypatch):
    command = "echo\tTAB COMMAND"
    template = make_template(tmp_path, command + "\n")
    called = {}
    monkeypatch.setattr(bd, "fzf", lambda lines, header="", query=None: command)

    def fake_run(cmd, shell=False):
        called.update(cmd=cmd, shell=shell)
        return 0

    monkeypatch.setattr(bd, "run", fake_run)

    assert bd.dispatch(str(template)) == 0
    assert called == {"cmd": command, "shell": True}


def test_root_menu_combines_commands_with_dispatchable_entries(tmp_path):
    template = make_template(tmp_path, "echo READY\ngit.txt\n")
    (template / "git.txt").write_text("echo NESTED\n")
    (template / "notes.md").write_text("# Notes\n")
    (template / "ignored.json").write_text("{}\n")
    (template / ".hidden.sh").write_text("echo HIDDEN\n")
    (template / "starter").mkdir()

    assert bd.menu(str(template), "") == ["echo READY", "git.txt", "notes.md", "starter"]


def test_submenu_runs_a_command(tmp_path, monkeypatch, capsys):
    template = make_template(tmp_path, "git.txt\n")
    (template / "git.txt").write_text("echo NESTED\n")
    selections = iter(["git.txt", "echo NESTED"])
    monkeypatch.setattr(bd, "fzf", lambda lines, header="", query=None: next(selections))

    assert bd.dispatch(str(template)) == 0
    assert "NESTED" in capsys.readouterr().out


def test_query_arguments_follow_nested_menus(tmp_path, monkeypatch):
    template = make_template(tmp_path, "yarn.txt\n")
    (template / "yarn.txt").write_text("yarn build\nyarn dev\n")
    queries = []
    headers = []
    executed = []

    def fake_fzf(lines, header="", query=None):
        queries.append(query)
        headers.append(header)
        return "yarn.txt" if len(queries) == 1 else "yarn dev"

    monkeypatch.setattr(bd, "fzf", fake_fzf)
    monkeypatch.setattr(bd, "execute", lambda template_dir, line: executed.append(line) or 0)
    monkeypatch.setattr(bd.shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(bd.sys, "argv", ["bd", "yarn", "dev"])

    with pytest.raises(SystemExit) as result:
        bd.main(str(template))

    assert result.value.code == 0
    assert queries == ["yarn", "dev"]
    assert headers == [str(template), str(template / "yarn.txt")]
    assert executed == ["yarn dev"]


def test_script_gets_exact_args_and_failure_propagates(tmp_path, capfd):
    template = make_template(tmp_path)
    (template / "args.sh").write_text('echo "[$1][$2]"\nexit 3\n')

    result = bd.execute(str(template), 'args.sh "a b" c')

    assert result == 3
    assert "[a b][c]" in capfd.readouterr().out


def test_markdown_resolves_to_the_pager(tmp_path):
    template = make_template(tmp_path)
    (template / "notes.md").write_text("# Notes\n")

    command, shell = bd.resolve(str(template), "notes.md")

    assert command == ["less", str(template / "notes.md")]
    assert shell is False


def test_folder_opens_a_file_picker_and_copies_only_the_selected_file(tmp_path, monkeypatch, capsys):
    template = make_template(tmp_path, "starter\n")
    starter = template / "starter"
    starter.mkdir()
    (starter / "config.yml").write_text("name: demo\n")
    (starter / "nested.txt").write_text("not a command here\n")
    selections = iter(["starter", "config.yml"])
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(bd, "fzf", lambda lines, header="", query=None: next(selections))
    monkeypatch.setattr(bd, "confirm", lambda prompt: True)

    assert bd.dispatch(str(template)) == 0
    assert (tmp_path / "config.yml").read_text() == "name: demo\n"
    assert not (tmp_path / "starter").exists()
    assert "config.yml" in capsys.readouterr().out


def test_folder_copy_without_destination_does_not_confirm(tmp_path, monkeypatch):
    template = make_template(tmp_path)
    folder = template / "starter"
    folder.mkdir()
    (folder / "config.yml").write_text("name: demo\n")
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(bd, "confirm", lambda prompt: pytest.fail("confirmation should not be requested"))

    assert bd.copy_file(str(template), "starter/config.yml") == 0
    assert (tmp_path / "config.yml").read_text() == "name: demo\n"


def test_folder_copy_keeps_existing_file_when_overwrite_is_declined(tmp_path, monkeypatch):
    template = make_template(tmp_path)
    folder = template / "starter"
    folder.mkdir()
    (folder / "config.yml").write_text("name: demo\n")
    (tmp_path / "config.yml").write_text("name: local\n")
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(bd, "confirm", lambda prompt: False)

    assert bd.copy_file(str(template), "starter/config.yml") == 0
    assert (tmp_path / "config.yml").read_text() == "name: local\n"


def test_folder_copy_overwrites_existing_file_when_confirmed(tmp_path, monkeypatch):
    template = make_template(tmp_path)
    folder = template / "starter"
    folder.mkdir()
    (folder / "config.yml").write_text("name: demo\n")
    (tmp_path / "config.yml").write_text("name: local\n")
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(bd, "confirm", lambda prompt: True)

    assert bd.copy_file(str(template), "starter/config.yml") == 0
    assert (tmp_path / "config.yml").read_text() == "name: demo\n"


def test_folder_copy_refuses_symlinks(tmp_path, monkeypatch, capsys):
    template = make_template(tmp_path)
    folder = template / "starter"
    folder.mkdir()
    source = folder / "config.yml"
    source.write_text("name: demo\n")
    target = tmp_path / "target.yml"
    target.write_text("name: target\n")
    destination = tmp_path / "config.yml"
    destination.symlink_to(target)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(bd, "confirm", lambda prompt: pytest.fail("confirmation should not be requested"))

    assert bd.copy_file(str(template), "starter/config.yml") == 1
    assert destination.is_symlink()
    destination.unlink()
    source.unlink()
    source.symlink_to(target)
    assert bd.copy_file(str(template), "starter/config.yml") == 1
    assert not (tmp_path / "config.yml").exists()
    assert target.read_text() == "name: target\n"
    assert capsys.readouterr().err.count("refusing to copy symlink") == 2
