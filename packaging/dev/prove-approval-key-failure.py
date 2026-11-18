# Run only the T35 approval-key failure proof using the existing Swift proof setup.
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / "ios/BogoKit"
SWIFTC = ["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library"]
with tempfile.TemporaryDirectory(prefix="bogo-key-failure-") as temporary:
    out = Path(temporary)
    linked = ["-I", temporary, "-L", temporary, "-Xlinker", "-rpath", "-Xlinker", temporary]
    # Fault injection only in a temporary compilation input. No authentication
    # dialog, Keychain write, or change to a product source file.
    approval = (KIT / "BogoCrypto/ApprovalKey.swift").read_text()
    original = "return try await SecureEnclaveApprovalKey.create(account: account, reason: reason, proving: message)"
    assert original in approval
    injected = out / "ApprovalKey.swift"
    injected.write_text(approval.replace(original, "throw KeychainError.status(-34018)"))
    for module, needs in [("BogoModel", []), ("BogoCrypto", ["BogoModel"])]:
        sources = sorted((KIT / module).glob("*.swift"))
        sources = [injected if p.name == "ApprovalKey.swift" else p for p in sources]
        library = out / f"lib{module}.dylib"
        subprocess.run([*SWIFTC, "-emit-library", "-emit-module", "-module-name", module,
            *linked, *[f"-l{need}" for need in needs], *map(str, sources), "-o", str(library),
            "-Xlinker", "-install_name", "-Xlinker", f"@rpath/{library.name}"], check=True)
    fixture = out / "RoomFixture.swift"
    fixture.write_text((ROOT / "lab/ios/BogoClosedRoomProof.swift").read_text().split("@main")[0])
    binary = out / "approval-key-failure"
    subprocess.run([*SWIFTC, *linked, "-lBogoModel", "-lBogoCrypto",
        *map(str, sorted((KIT / "BogoRelay").glob("*.swift"))), str(fixture),
        str(ROOT / "lab/ios/BogoApprovalKeyFailureProof.swift"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], cwd=temporary, check=True)
