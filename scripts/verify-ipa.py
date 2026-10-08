import argparse
import hashlib
import json
import plistlib
import re
import struct
import zipfile
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_snapshot(content):
    report = json.loads(content)
    require(report.get("schemaVersion") == 1, "Unsupported snapshot schema")
    require(report.get("vendorId") == "2CA3" and report.get("productId") == "4009", "Wrong USB target")
    require(isinstance(report.get("capturedAt"), str) and report["capturedAt"], "Missing capture timestamp")
    require(isinstance(report.get("interfaces"), list) and report["interfaces"], "Missing interfaces")
    require(isinstance(report.get("limitations"), list) and report["limitations"], "Missing evidence limitations")
    require(isinstance(report.get("serialPortNames"), list), "Invalid serial port names")
    require(all(re.fullmatch(r"COM\d+", port) for port in report["serialPortNames"]), "Invalid COM name")
    numbers = [record["number"] for record in report["interfaces"]]
    require(len(set(numbers)) == len(numbers), "Duplicate interface numbers")
    require(all(re.fullmatch(r"[0-9A-F]{2}", number) for number in numbers), "Invalid interface numbers")
    for record in [report["device"], *report["interfaces"]]:
        require(re.fullmatch(r"USB\\VID_2CA3&PID_4009(?:&MI_[0-9A-F]{2})?\\<redacted>", record["instanceId"]), "Unredacted or invalid instance ID")
        require(isinstance(record.get("hardwareIds"), list) and record["hardwareIds"], "Missing hardware IDs")
        require(isinstance(record.get("compatibleIds"), list), "Invalid compatible IDs")
        require(isinstance(record.get("status"), str), "Missing driver status")
        require(record.get("problemCode") is None or isinstance(record["problemCode"], int), "Invalid problem code")
        for field in ("classCode", "subclassCode", "protocolCode"):
            value = record.get(field)
            require(value is None or re.fullmatch(r"[0-9A-F]{2}", value), "Invalid USB class field")
    return report


def validate_ipa(ipa_path, commit):
    bundle_path = "Payload/DJICellularPhone.app/"
    with zipfile.ZipFile(ipa_path) as archive:
        require(archive.testzip() is None, "Corrupt IPA archive")
        info = plistlib.loads(archive.read(bundle_path + "Info.plist"))
        require(info.get("CFBundleIdentifier") == "com.bibilabusensei.DJICellularPhone", "Wrong bundle ID")
        require(set(info.get("UIDeviceFamily", [])) == {1, 2}, "IPA must support both iPhone and iPad")
        require("iPhoneOS" in info.get("CFBundleSupportedPlatforms", []), "Not a device build")
        require(info.get("MinimumOSVersion") == "17.0", "Unexpected minimum OS")
        ipad_orientations = info.get("UISupportedInterfaceOrientations~ipad", info.get("UISupportedInterfaceOrientations", []))
        require(set(ipad_orientations) == {
            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
        }, "iPad multitasking requires all four orientations")
        executable = archive.read(bundle_path + info["CFBundleExecutable"])
        require(len(executable) >= 32 and executable[:4] == b"\xcf\xfa\xed\xfe", "Missing 64-bit Mach-O executable")
        require(struct.unpack_from("<I", executable, 4)[0] == 0x0100000C, "Device executable must be arm64")
        require(bundle_path + "embedded.mobileprovision" not in archive.namelist(), "Unexpected provisioning profile")
        report = validate_snapshot(archive.read(bundle_path + "IG831T-USB-Snapshot.json"))
    digest = hashlib.sha256(ipa_path.read_bytes()).hexdigest()
    return {
        "commit": commit,
        "sha256": digest,
        "bundleIdentifier": info["CFBundleIdentifier"],
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "minimumOS": info["MinimumOSVersion"],
        "deviceFamilies": info["UIDeviceFamily"],
        "ipadOrientations": ipad_orientations,
        "architecture": "arm64",
        "codeSigningAllowed": False,
        "provisioningProfileIncluded": False,
        "installation": "Separate valid signing/provisioning is required; no DriverKit entitlement is granted by this IPA.",
        "hardwareSnapshotCapturedAt": report["capturedAt"],
        "hardwareSnapshotIsLive": False,
        "realUSBTransportImplemented": False,
        "realCellularCallsImplemented": False,
        "realCellularInternetImplemented": False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path, nargs="?")
    parser.add_argument("--snapshot", type=Path)
    parser.add_argument("--commit", default="unknown")
    parser.add_argument("--manifest", type=Path)
    arguments = parser.parse_args()
    if arguments.snapshot:
        report = validate_snapshot(arguments.snapshot.read_bytes())
        print(f"Snapshot validated: {report['vendorId']}:{report['productId']}, {len(report['interfaces'])} interfaces; not live.")
    if arguments.ipa:
        manifest = validate_ipa(arguments.ipa, arguments.commit)
        if arguments.manifest:
            arguments.manifest.parent.mkdir(parents=True, exist_ok=True)
            arguments.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(manifest, ensure_ascii=False, indent=2))
    if not arguments.snapshot and not arguments.ipa:
        parser.error("Provide --snapshot or an IPA path")


if __name__ == "__main__":
    main()
