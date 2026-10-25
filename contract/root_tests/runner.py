"""Run the Root black-box checks: python -m contract.root_tests.runner  (needs both Root builds, see control-plane/arm64)"""
import sys
import time

from contract.root_tests import checks_abuse, checks_agents, checks_apps, checks_auth, checks_brain, checks_cpu_options, checks_gpu, checks_gpu_limit, checks_gpu_stats, checks_hardware, checks_helper_update, checks_history, checks_images, checks_machine_page, checks_monitor, checks_public, checks_public_site, checks_remote, checks_remote_fix, checks_remote_gpu, checks_remote_install, checks_sandbox_ports, checks_scan, checks_ssh_keys, checks_ssh_setup, checks_stopped_reason, checks_terminal, checks_terminal_linux

ALL_CHECKS = checks_public.CHECKS + checks_public_site.CHECKS + checks_auth.CHECKS + checks_agents.CHECKS + checks_abuse.CHECKS + checks_brain.CHECKS + checks_gpu.CHECKS + checks_helper_update.CHECKS + checks_scan.CHECKS + checks_remote.CHECKS + checks_remote_fix.CHECKS + checks_remote_gpu.CHECKS + checks_remote_install.CHECKS + checks_machine_page.CHECKS + checks_terminal.CHECKS + checks_terminal_linux.CHECKS + checks_monitor.CHECKS + checks_stopped_reason.CHECKS + checks_images.CHECKS + checks_history.CHECKS + checks_gpu_stats.CHECKS + checks_ssh_keys.CHECKS + checks_ssh_setup.CHECKS + checks_apps.CHECKS + checks_gpu_limit.CHECKS + checks_cpu_options.CHECKS + checks_hardware.CHECKS + checks_sandbox_ports.CHECKS


def main():
    failures = 0
    wanted = sys.argv[1:]  # optional: only the checks whose name holds one of these words
    checks = [check for check in ALL_CHECKS if not wanted or any(word in check.__name__ for word in wanted)]
    for check in checks:
        started = time.time()
        try:
            check()
        except checks_scan.Skip as why:
            print(f"SKIP  {check.__name__}: {why}")
            continue
        except Exception as error:  # noqa: BLE001 - any crash is a failed check
            failures += 1
            print(f"FAIL  {check.__name__}: {error!r}")
            continue
        print(f"PASS  {check.__name__} ({time.time() - started:.1f}s)")
    print(f"\n{len(checks) - failures} passed, {failures} failed, {len(checks)} checks")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
