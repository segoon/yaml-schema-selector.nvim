import json
import os
import subprocess
import sys

import yaml


ARC_ROOT = subprocess.check_output(["arc", "root"], encoding="utf8").strip()


def read_cmy(fname):
    with open(fname, "r") as ifile:
        return yaml.safe_load(ifile)


def read_plugin_paths(content):
    return [key for key in content if "/" in key]


def read_plugin_schema(plugin_path):
    fname = os.path.join(ARC_ROOT, plugin_path, "codegen-plugin.yaml")
    with open(fname, "r") as ifile:
        try:
            return yaml.safe_load(ifile)["code"]["uservices"]["schema"]
        except KeyError:
            return {}


def make_schema(content):
    schema = {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "framework": {"const": "uservices"},
            "type": {"type": "string"},
        },
    }

    for plugin in read_plugin_paths(content):
        schema["properties"][plugin] = read_plugin_schema(plugin)
    return schema


def main():
    content = read_cmy(sys.argv[1])
    print(json.dumps(make_schema(content)))


if __name__ == "__main__":
    main()
