"""The NVIDIA container toolkit row of the check list and its "Install it for me". Same pretend Debian as checks_remote_fix.py: its sudo, apt-get, curl, gpg and
install are stubs, so NVIDIA's package source is never reached and nothing outside the fake folder is written. The sudo password is a recognizable fake."""
from contract.root_tests.checks_remote import rows, verify_body
from contract.root_tests.checks_remote_fix import FIX, fake_computer, fix_body, leaks
from contract.root_tests.fakes.fake_linux import PASSWORD
from contract.root_tests.support import expect

VERIFY = "/api/remote/verify"
ROW = "gpu_toolkit"


def check_the_toolkit_row_exists_only_on_a_computer_with_an_nvidia_card():
    with fake_computer() as (root, operator, server):
        expect(ROW not in rows(operator.write("POST", VERIFY, verify_body(server))), "a computer without a card must not get the row")
        server.state("nvidia")
        table = rows(operator.write("POST", VERIFY, verify_body(server)))
        expect(ROW in table and table[ROW]["ok"] is False, f"a card without the toolkit is a cross: {table.get(ROW)}")
        expect("RTX 5090" in table[ROW]["detail"] and "docs.nvidia.com" in table[ROW]["fix"], f"the row names the card and the doc: {table[ROW]}")
        expect(table[ROW]["install"] == {"part": "gpu_toolkit", "needs_password": True}, f"offer: {table[ROW]}")
        server.state("nvidia_toolkit")
        expect(rows(operator.write("POST", VERIFY, verify_body(server)))[ROW]["ok"] is True, "the toolkit makes it a tick")


def check_a_system_that_is_not_apt_gets_the_manual_line_only():
    with fake_computer() as (root, operator, server):
        server.state("nvidia")
        server._file("answer.txt", open(f"{server.dir}/answer.txt").read().replace("pkg=apt", "pkg=dnf"))
        row = rows(operator.write("POST", VERIFY, verify_body(server)))[ROW]
        expect("install" not in row and "docs.nvidia.com" in row["fix"], f"dnf: manual line only: {row}")


def check_install_it_for_me_adds_nvidias_source_installs_the_toolkit_and_checks_again():
    with fake_computer() as (root, operator, server):
        server.state("nvidia")
        reply = operator.write("POST", FIX, fix_body(server, part="gpu_toolkit"))
        expect(reply.status == 200, f"fix: {reply.status} {reply.raw[:300]!r}")
        expect(rows(reply)[ROW]["ok"] is True and "install" not in rows(reply)[ROW], f"the row is a tick now: {rows(reply)[ROW]}")
        log = server.commands()
        steps = ["nvidia.github.io/libnvidia-container/gpgkey", "gpg --dearmor", "stable/deb/nvidia-container-toolkit.list", "install -m 0644", "install nvidia-container-toolkit"]
        positions = [log.find(step) for step in steps]
        expect(all(position >= 0 for position in positions) and positions == sorted(positions), f"NVIDIA's steps, in order: {positions} in {log[-900:]}")
        expect("signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg" in open(f"{server.dir}/nvidia-source.list").read(), "the source is signed by the key")
        expect("incus" not in log, "installing the toolkit must not touch Incus")


def check_the_toolkit_install_never_leaks_the_password_and_fails_in_plain_words():
    with fake_computer() as (root, operator, server):
        server.state("nvidia")
        replies = [operator.write("POST", FIX, fix_body(server, part="gpu_toolkit"))]
        found = leaks(PASSWORD, root, operator, server, replies)
        expect(not found, f"the sudo password leaked into: {found}")
    with fake_computer() as (root, operator, server):
        server.state("nvidia")
        server.state("no_network")
        reply = operator.write("POST", FIX, fix_body(server, part="gpu_toolkit"))
        expect(reply.status == 502 and reply.body["error"]["code"] == "remote_install_failed", f"no network: {reply.status} {reply.raw[:300]!r}")
        expect(not server.has("nvidia_toolkit"), "a failed install leaves no toolkit")


def check_the_toolkit_is_not_offered_where_there_is_no_card():
    with fake_computer() as (root, operator, server):
        reply = operator.write("POST", FIX, fix_body(server, part="gpu_toolkit"))
        expect(reply.status == 409 and reply.body["error"]["code"] == "remote_fix_unavailable", f"no card: {reply.status} {reply.raw[:200]!r}")
        expect("sudo" not in server.commands(), "nothing may be run where the install is not offered")


CHECKS = [check_the_toolkit_row_exists_only_on_a_computer_with_an_nvidia_card, check_a_system_that_is_not_apt_gets_the_manual_line_only,
          check_install_it_for_me_adds_nvidias_source_installs_the_toolkit_and_checks_again, check_the_toolkit_install_never_leaks_the_password_and_fails_in_plain_words,
          check_the_toolkit_is_not_offered_where_there_is_no_card]
