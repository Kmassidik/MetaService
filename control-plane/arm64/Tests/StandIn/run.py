"""Runs XCTest-style test files with swiftc and the stand-in, where XCTest is not installed (command line tools only).

    python3 Tests/StandIn/run.py core    # RootCoreTests/Mcp against the real RootCore
    python3 Tests/StandIn/run.py store   # RootStoreTests/Mcp against the real RootStore

It compiles the real sources into a module, the real test files, and a main that is written here from the test files: every `func testX()` of every
`final class Name: XCTestCase` is called, with setUpWithError and setUp before it. Nothing is installed or changed on the machine.
"""
import pathlib
import re
import subprocess
import sys
import tempfile

PACKAGE = pathlib.Path(__file__).resolve().parents[2]
SHARED = PACKAGE.parents[1] / "shared" / "metaservice-shared" / "Sources" / "MSCore"
COMMON = ["-swift-version", "5", "-Onone", "-enable-testing"]


def sources(folder):
    return sorted(str(path) for path in folder.rglob("*.swift"))


def module(name, files, out, deps=(), link=()):
    command = ["swiftc", *COMMON, "-parse-as-library", "-module-name", name, "-emit-module", "-emit-module-path", str(out / f"{name}.swiftmodule"),
               "-emit-library", "-static", "-o", str(out / f"lib{name}.a"), "-I", str(out), *files]
    subprocess.run(command, check=True)


def main():
    kind = sys.argv[1] if len(sys.argv) > 1 else "core"
    out = pathlib.Path(tempfile.mkdtemp(prefix="ms-standin-"))
    tests = sources(PACKAGE / "Tests" / ("RootCoreTests" if kind == "core" else "RootStoreTests") / "Mcp")
    module("XCTest", [str(pathlib.Path(__file__).with_name("XCTestStandIn.swift"))], out)
    module("MSCore", sources(SHARED), out)
    module("RootCore", sources(PACKAGE / "Sources" / "RootCore"), out)
    imports = ["RootCore"]
    libs = [str(out / "libRootCore.a"), str(out / "libMSCore.a")]
    if kind == "store":
        module("RootStore", sources(PACKAGE / "Sources" / "RootStore"), out)
        imports.append("RootStore")
        libs.insert(0, str(out / "libRootStore.a"))
    calls = []
    for path in tests:
        text = pathlib.Path(path).read_text()
        for match in re.finditer(r"final class (\w+): XCTestCase \{(.*?)\n\}\n", text, re.S):
            cls, body = match.groups()
            for test in re.finditer(r"func (test\w+)\(\)( throws)?", body):
                calls.append(f'runStandInTest("{cls}.{test.group(1)}") {{ let t = {cls}(); try t.setUpWithError(); t.setUp(); {"try " if test.group(2) else ""}t.{test.group(1)}(); t.tearDown() }}')
    main_file = out / "main.swift"
    main_file.write_text("import Foundation\nimport XCTest\n" + "".join(f"@testable import {name}\n" for name in imports) + "\n".join(calls) + "\nfinishStandIn()\n")
    binary = out / "run-tests"
    subprocess.run(["swiftc", *COMMON, "-I", str(out), "-lsqlite3", "-o", str(binary), str(main_file), *tests, str(out / "libXCTest.a"), *libs], check=True)
    sys.exit(subprocess.run([str(binary)]).returncode)


if __name__ == "__main__":
    main()
