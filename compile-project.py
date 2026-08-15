#!/usr/bin/env python3
"""Direct Keil C51 toolchain builder (bypasses UV4 subprocess issues)."""
import subprocess
import sys
import os
import xml.etree.ElementTree as ET

CONTAINER = "keil-wine"
WORK = "/home/wineuser/work"
C51_BIN = "/home/wineuser/.wine/drive_c/Keil_v5/C51/BIN"

def run_cmd(cmd, verbose=True):
    result = subprocess.run(["docker", "exec", CONTAINER, "sh", "-c", cmd],
                            capture_output=True, text=True)
    if verbose and result.stdout:
        for line in result.stdout.strip().split("\n"):
            if not any(s in line for s in ["fixme:", "err:ntoskrnl", "err:ole"]):
                print("  " + line)
    return result.returncode

def run_quiet(cmd):
    return run_cmd(cmd, verbose=False)

def parse_uvproj(proj_path):
    tree = ET.parse(proj_path)
    root = tree.getroot()
    sources = []
    for fe in root.iter("File"):
        name = fe.find("FileName").text
        path = fe.find("FilePath").text
        ftype = int(fe.find("FileType").text)
        sources.append({"name": name, "path": path, "type": ftype})
    return sources

def win2ux(p):
    p = p.replace("\\", "/")
    return p.lstrip("./")

def write_inv(container_path, lines):
    content = "\\n".join(lines)
    run_quiet(f"cd {container_path} && printf '{content}\\n' > _build.inv")

def main():
    if len(sys.argv) < 2:
        print("Usage: compile-project.sh <project_folder> [rebuild]")
        sys.exit(1)

    project_dir = os.path.realpath(sys.argv[1])
    if not os.path.isdir(project_dir):
        print(f"Error: Directory not found: {project_dir}")
        sys.exit(1)

    uvproj = next((f for f in os.listdir(project_dir) if f.endswith(".uvproj")), None)
    if not uvproj:
        print(f"Error: No .uvproj file found in {project_dir}")
        sys.exit(1)

    project_name = uvproj.replace(".uvproj", "")
    print(f"Project: {project_name}")
    print(f"Source:  {project_dir}")

    result = subprocess.run(["docker", "inspect", CONTAINER], capture_output=True)
    if result.returncode != 0:
        print(f"Error: Container '{CONTAINER}' not found.")
        sys.exit(1)

    # Copy project
    print("Copying project to container...")
    run_quiet(f"mkdir -p {WORK}")
    subprocess.run(["docker", "cp", f"{project_dir}/.", f"{CONTAINER}:{WORK}/{project_name}/"], check=True)

    sources = parse_uvproj(os.path.join(project_dir, uvproj))
    proj = f"{WORK}/{project_name}"

    # Assemble .A51 files via invoke file
    for s in sources:
        if s["name"].upper().endswith(".A51"):
            p = win2ux(s["path"])
            base = os.path.splitext(os.path.basename(p))[0]
            obj_path = f"Objects/{base}.OBJ"
            lst_path = f"Listings/{base}.lst"
            print(f"Assembling {p}...")
            inv_lines = [
                p,
                f"OBJ({obj_path})",
                f"LIST({lst_path})",
                "NOMOD51",
            ]
            write_inv(proj, inv_lines)
            rc = run_cmd(f"cd {proj} && wine {C51_BIN}/A51.EXE @_build.inv")
            run_quiet(f"rm -f {proj}/_build.inv")

    # Compile C sources via invoke files
    for s in sources:
        if s["type"] == 1:
            p = win2ux(s["path"])
            print(f"Compiling {p}...")
            inv_lines = [
                p,
                "INCDIR(H/)",
                "OPTIMIZE(8)",
                "DEBUG",
                "OBJECTEXTEND",
                "CODE",
            ]
            write_inv(proj, inv_lines)
            rc = run_cmd(f"cd {proj} && wine {C51_BIN}/C51.EXE @_build.inv")
            run_quiet(f"rm -f {proj}/_build.inv")

    # Collect all .OBJ files
    print("Linking...")
    obj_files = []
    for s in sources:
        if s["name"].upper().endswith(".OBJ"):
            obj_files.append(win2ux(s["path"]))
        elif s["type"] == 1:
            base = os.path.splitext(os.path.basename(win2ux(s["path"])))[0]
            obj_files.append(f"Objects/{base}.OBJ")
        elif s["name"].upper().endswith(".A51"):
            base = os.path.splitext(os.path.basename(win2ux(s["path"])))[0]
            obj_files.append(f"Objects/{base}.OBJ")

    # Write linker invoke file
    inv_lines = [",".join(obj_files), f"TO Objects/{project_name}", f"PRINT(Listings/{project_name}.m51)", "RAMSIZE(256)"]
    write_inv(proj, inv_lines)
    run_cmd(f"cd {proj} && wine {C51_BIN}/LX51.EXE @_build.inv")
    run_quiet(f"rm -f {proj}/_build.inv")

    # Generate HEX
    print("Generating HEX...")
    run_cmd(f"cd {proj} && wine {C51_BIN}/OH51.EXE {project_name}")

    # Copy back
    output_dir = os.path.join(project_dir, "Objects")
    os.makedirs(output_dir, exist_ok=True)

    print("\nCopying output files...")
    for ext in ["hex", "HEX", "map", "MAP", "OBJ", "obj", "lst", "LST", "htm", "HTM"]:
        subprocess.run(["docker", "cp", f"{CONTAINER}:{proj}/.{ext}", f"{output_dir}/"],
                        capture_output=True)

    print("\nBuild output:")
    if os.path.isdir(output_dir):
        for f in sorted(os.listdir(output_dir)):
            fp = os.path.join(output_dir, f)
            if os.path.isfile(fp):
                print(f"  {f} ({os.path.getsize(fp)} bytes)")

    run_quiet(f"rm -rf {proj}")
    print("\nDone.")

if __name__ == "__main__":
    main()
