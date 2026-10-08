"""Loads contract/openapi.yaml and validates JSON against its schemas.

One source of truth: the Fake Agent and the conformance tests both validate with this file.
"""
import copy
import pathlib

import jsonschema
import yaml

SPEC_PATH = pathlib.Path(__file__).with_name("openapi.yaml")


def _allow_null(node):
    """OpenAPI 3.0 says `nullable: true`; JSON Schema wants a type list."""
    if isinstance(node, list):
        for item in node:
            _allow_null(item)
        return
    if not isinstance(node, dict):
        return
    if node.pop("nullable", False) and "type" in node:
        node["type"] = [node["type"], "null"]
    for value in node.values():
        _allow_null(value)


def load_spec():
    spec = yaml.safe_load(SPEC_PATH.read_text())
    spec = copy.deepcopy(spec)
    _allow_null(spec)
    return spec


SPEC = load_spec()
CONTRACT_VERSION = SPEC["info"]["version"]
CONTRACT_HEADER = "X-MetaService-Contract"


def _validator(schema_name):
    root = {"$ref": f"#/components/schemas/{schema_name}", "components": SPEC["components"]}
    return jsonschema.Draft7Validator(root)


_VALIDATORS = {name: _validator(name) for name in SPEC["components"]["schemas"]}


def problems(schema_name, instance):
    """Return a list of readable problems; empty means the instance fits the schema."""
    validator = _VALIDATORS[schema_name]
    return [
        f"{'/'.join(str(p) for p in error.absolute_path) or '(root)'}: {error.message}"
        for error in validator.iter_errors(instance)
    ]
