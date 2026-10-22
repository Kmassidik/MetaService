"""Run the Fake Agent by hand: python -m agent.fake --port 9110 --token-file path"""
import argparse
import pathlib

from agent.fake.engine import DEFAULT_AGENT_BUILD, GPU_INSIDE, FakeEngine, MachineSpec
from agent.fake.server import make_server
from agent.fake.stats import FakeStats
from agent.fake.stats_extras import EXTRAS_FULL, EXTRAS_KINDS


def main():
    parser = argparse.ArgumentParser(description="MetaService Fake Agent (test tool)")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9110)
    parser.add_argument("--token-file", required=True, help="file holding the machine token")
    parser.add_argument("--cores", type=int, default=8, help="how many cores /v1/stats reports")
    parser.add_argument("--physical", type=int, help="physical cores (default: as many as --cores; 16 with --cores 32 is a 16 core, 32 thread machine)")
    parser.add_argument("--extras", choices=EXTRAS_KINDS, default=EXTRAS_FULL, help="which optional numbers /v1/stats sends: full (Linux), mac, or none (an older helper)")
    parser.add_argument("--gpu", action="store_true", help="/v1/stats reports one NVIDIA card")
    parser.add_argument("--nvidia", choices=["toolkit", "no-toolkit"], help="the facts report an NVIDIA card; with the container toolkit containers can use it, without it they cannot")
    parser.add_argument("--gpu-inside", choices=sorted(GPU_INSIDE), default="nvidia-smi", help="what the GPU check finds inside a container")
    parser.add_argument("--agent-build", default=DEFAULT_AGENT_BUILD, help="the build (64 lowercase hex digits) the facts report; 'none' reports no build, like an older helper")
    args = parser.parse_args()
    token = pathlib.Path(args.token_file).read_text().strip()
    has_card = args.nvidia is not None
    card = [{"vendor": "nvidia", "model": "NVIDIA GeForce RTX 5090", "memory_mb": 32768}] if has_card else []
    spec = MachineSpec(vm=not has_card, gpu=card, gpu_in_container=args.nvidia == "toolkit", gpu_inside=args.gpu_inside)
    build = None if args.agent_build == "none" else args.agent_build
    server = make_server(FakeEngine(spec, agent_build=build), token, args.host, args.port, FakeStats(cores=args.cores, gpu=args.gpu or has_card, physical=args.physical, extras=args.extras))
    print(f"Fake Agent on http://{args.host}:{server.server_address[1]}")
    server.serve_forever()


if __name__ == "__main__":
    main()
