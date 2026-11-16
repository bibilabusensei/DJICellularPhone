import argparse
import hashlib
import json
import zipfile
from pathlib import Path


def verify(path, commit):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None or "classes.dex" not in archive.namelist():
            raise ValueError("Invalid APK")
        capabilities = json.loads(archive.read("assets/capabilities.json"))
        if capabilities.get("minimumAndroidApi") != 21 or capabilities.get("targetAndroidApi") != 35:
            raise ValueError("Unexpected API contract")
        for field in ("twoWayCallAudioImplemented", "userspaceModemDataDriverImplemented",
                      "systemCellularNetworkIntegrationImplemented", "androidHardwareValidated",
                      "android5RuntimeValidated", "android11RuntimeValidated", "firmwareOrUsbModeChangesImplemented"):
            if capabilities.get(field) is not False:
                raise ValueError("Unsupported capability claim: " + field)
    return {
        "commit": commit,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "package": "com.bibilabusensei.djicellular.android",
        "version": "0.1.0",
        "signing": "Ephemeral CI debug key, not production signing; next build may require uninstall before install.",
        "capabilities": capabilities,
        "hardwareTestsPerformed": False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    arguments = parser.parse_args()
    manifest = verify(arguments.apk, arguments.commit)
    arguments.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
