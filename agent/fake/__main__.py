"""Run the Fake Agent by hand: python -m agent.fake --port 9110 --token-file path"""
import argparse
import pathlib

from agent.fake.engine import FakeEngine
from agent.fake.server import make_server


def main():
    parser = argparse.ArgumentParser(description="MetaService Fake Agent (test tool)")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9110)
    parser.add_argument("--token-file", required=True, help="file holding the machine token")
    args = parser.parse_args()
    token = pathlib.Path(args.token_file).read_text().strip()
    server = make_server(FakeEngine(), token, args.host, args.port)
    print(f"Fake Agent on http://{args.host}:{server.server_address[1]}")
    server.serve_forever()


if __name__ == "__main__":
    main()
