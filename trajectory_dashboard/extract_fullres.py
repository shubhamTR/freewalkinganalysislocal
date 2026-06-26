#!/usr/bin/env python3
"""
extract_fullres.py — Extract full-resolution trajectory data for the interactive dashboard.

Reads trx.mat, arena_calib_*.mat, LED_detector_*.mat, and original_metadata.txt
from each experiment, and produces per-protocol JSON files + updated manifest.json
+ updated index.html dropdown.

Usage:
    python3 extract_fullres.py P023 P024 P025          # specific protocols
    python3 extract_fullres.py --all                    # all protocols with experiments
    python3 extract_fullres.py P017 --analysis-dir /path/to/data

The script merges into existing JSON and manifest files (doesn't overwrite other protocols).
"""

import argparse
import glob
import json
import os
import re
import sys
from pathlib import Path

import numpy as np
import scipy.io as sio

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEFAULT_ANALYSIS_DIR = "/Users/rathores/Documents/analysisdatalocal"
SCRIPT_DIR = Path(__file__).resolve().parent  # trajectory_dashboard/


def load_mat_v5(path):
    """Load a v5 .mat file. Returns dict or raises NotImplementedError for v7.3."""
    return sio.loadmat(path, squeeze_me=True, struct_as_record=False)


def load_trx(path):
    """
    Load trx.mat (v5 or v7.3 HDF5).
    Returns (fly_x_list, fly_y_list, first_frames_list).
    Each is a list of length n_flies with numpy arrays.
    """
    import h5py

    try:
        data = sio.loadmat(path, squeeze_me=True, struct_as_record=False)
        trx = data["trx"]
        if not hasattr(trx, "__len__"):
            trx = [trx]
        n_flies = len(trx)

        fly_x = []
        fly_y = []
        first_frames = []
        for i in range(n_flies):
            fly_x.append(np.array(trx[i].x, dtype=float).flatten())
            fly_y.append(np.array(trx[i].y, dtype=float).flatten())
            ff = int(trx[i].firstframe) if hasattr(trx[i], "firstframe") else 1
            first_frames.append(ff)
        return fly_x, fly_y, first_frames

    except NotImplementedError:
        # v7.3 HDF5 format — dereference object references
        f = h5py.File(path, "r")
        trx = f["trx"]
        x_refs = trx["x"]
        y_refs = trx["y"]
        ff_refs = trx["firstframe"]
        n_flies = x_refs.shape[0]

        fly_x = []
        fly_y = []
        first_frames = []
        for i in range(n_flies):
            fly_x.append(f[x_refs[i, 0]][()].flatten().astype(float))
            fly_y.append(f[y_refs[i, 0]][()].flatten().astype(float))
            first_frames.append(int(f[ff_refs[i, 0]][()].flatten()[0]))
        f.close()
        return fly_x, fly_y, first_frames


def parse_metadata_led_patterns(exp_path):
    """
    Parse original_metadata.txt to get per-cycle LED patterns and training patterns.
    Returns (led_patterns, training_patterns) — both lists of 4-char strings.
    Falls back to empty lists if metadata can't be parsed.
    """
    meta_file = os.path.join(exp_path, "original_metadata.txt")
    if not os.path.isfile(meta_file):
        meta_file = os.path.join(exp_path, "copy_metadata.txt")
    if not os.path.isfile(meta_file):
        return [], []

    with open(meta_file, "r", errors="replace") as f:
        lines = f.readlines()

    # --- Detect optomotor ---
    has_opto = any(
        "Optomotor Mode" in ln or "Phase 1: Red LED" in ln for ln in lines
    )

    # --- Parse ori-to-LED pairing ---
    # Matches both "Pairing: ori 0→1101" (P023) and "LED Pairing: led_ori 0→1101" (P024+)
    ori_to_led = {}
    for ln in lines:
        ln_s = ln.strip()
        if "Pairing:" in ln_s:
            toks = re.findall(r"ori\s+(\d+)\s*[→\->]+\s*(\d{4})", ln_s)
            for ori_s, led_s in toks:
                ori_to_led[int(ori_s)] = led_s

    # Fallback: standard 4-orientation SBD pairing used across P013–P027
    if not ori_to_led:
        ori_to_led = {0: "1101", 1: "1011", 2: "0111", 3: "1110"}

    # --- Try Randomized Orientation Log first (P017+) ---
    rand_start = None
    for i, ln in enumerate(lines):
        if "Randomized Orientation Log" in ln:
            rand_start = i + 1
            break

    led_patterns = []
    training_patterns = []

    if rand_start is not None:
        if has_opto:
            led_patterns.append("1111")
            training_patterns.append("1111")

        for li in range(rand_start, len(lines)):
            ln = lines[li].strip()
            if not ln or ln.startswith("===") or ln.startswith("---"):
                break

            led_match = re.search(r"LED=(\d{4})", ln)
            if not led_match:
                continue

            led_pat = led_match.group(1)
            led_patterns.append(led_pat)

            paired_match = re.search(r"paired_LED=(\d{4})", ln)
            if paired_match:
                training_patterns.append(paired_match.group(1))
            elif led_pat == "1111":
                ori_match = re.search(r"ori=(\d+)", ln)
                if ori_match and int(ori_match.group(1)) in ori_to_led:
                    training_patterns.append(ori_to_led[int(ori_match.group(1))])
                else:
                    training_patterns.append(led_pat)
            else:
                training_patterns.append(led_pat)

        if has_opto:
            led_patterns.append("1111")
            training_patterns.append("1111")

    else:
        # Fixed-order Block Schedule (P013 and older)
        sched_start = None
        for i, ln in enumerate(lines):
            if "Place Learning Block Schedule" in ln:
                sched_start = i + 1
                break

        if sched_start is None:
            return [], []

        if has_opto:
            led_patterns.append("1111")
            training_patterns.append("1111")

        for li in range(sched_start, len(lines)):
            ln = lines[li].strip()
            if not ln or ln.startswith("==="):
                break

            led_match = re.search(r"LED=(\d{4})", ln)
            if not led_match:
                continue
            led_pat = led_match.group(1)
            if led_pat == "RANDOM":
                continue

            led_patterns.append(led_pat)

            if led_pat == "1111":
                ori_match = re.search(r"ori=(\d+)", ln)
                if ori_match and int(ori_match.group(1)) in ori_to_led:
                    training_patterns.append(ori_to_led[int(ori_match.group(1))])
                else:
                    training_patterns.append(led_pat)
            else:
                training_patterns.append(led_pat)

        if has_opto:
            led_patterns.append("1111")
            training_patterns.append("1111")

    return led_patterns, training_patterns


def get_protocol_labels(protocol, num_cycles):
    """
    Generate default labels for a protocol based on cycle count.
    Only used as fallback when metadata parsing succeeds but labels are needed.
    """
    STRUCTURES = {
        48: (True, 4),   # OM + 4 blocks (P006-P016)
        46: (False, 4),  # 4 blocks no OM (P003, P005)
        42: (False, 0),  # intensity ramp (P001, P002)
        37: (True, 3),   # OM + 3 blocks (P013, P017, P019, P023, P024)
        26: (True, 2),   # OM + 2 blocks (P025)
        24: (False, 0),  # stepped intensity (P020, P021)
    }

    if num_cycles not in STRUCTURES:
        return [f"C{i+1}" for i in range(num_cycles)]

    has_om, n_blocks = STRUCTURES[num_cycles]

    if n_blocks == 0:
        return [f"C{i+1}" for i in range(num_cycles)]

    labels = []
    if has_om:
        labels.append("OM1")
    labels.append("PP")
    labels.append("Ag")

    for blk in range(1, n_blocks + 1):
        for t in range(1, 11):
            labels.append(f"B{blk}.{t}")
        labels.append(f"B{blk}.P")

    if has_om:
        labels.append("OM2")

    return labels[:num_cycles]


def extract_experiment(exp_path, protocol):
    """Extract trajectory data for one experiment. Returns (name, dict) or None."""
    exp_name = os.path.basename(exp_path)

    # --- Load trx.mat ---
    trx_file = os.path.join(exp_path, "trx.mat")
    if not os.path.isfile(trx_file):
        print(f"    SKIP {exp_name}: no trx.mat")
        return None

    try:
        all_fly_x, all_fly_y, all_first_frame = load_trx(trx_file)
    except Exception as e:
        print(f"    SKIP {exp_name}: trx load error: {e}")
        return None

    n_flies = len(all_fly_x)

    # --- Load arena calibration ---
    calib_files = glob.glob(os.path.join(exp_path, "analysis", "arena_calib_*.mat"))
    if not calib_files:
        print(f"    SKIP {exp_name}: no arena_calib")
        return None

    calib = load_mat_v5(calib_files[0])
    ac = calib["arena_calib"]
    xc = float(ac.xc)
    yc = float(ac.yc)
    r = float(ac.radius)

    # --- Load LED detector ---
    led_files = glob.glob(os.path.join(exp_path, "analysis", "LED_detector_*.mat"))
    if not led_files:
        print(f"    SKIP {exp_name}: no LED_detector")
        return None

    led_data = load_mat_v5(led_files[0])
    ld = led_data["LED_detector"]
    on_times = np.atleast_1d(ld.on_times).astype(int)
    off_times = np.atleast_1d(ld.off_times).astype(int)
    nc = len(on_times)

    if nc == 0:
        print(f"    SKIP {exp_name}: LED_detector has no cycles")
        return None

    # --- Parse metadata patterns ---
    led_patterns, training_patterns = parse_metadata_led_patterns(exp_path)

    if len(led_patterns) != nc:
        led_patterns = ["1111"] * nc
        training_patterns = ["1111"] * nc

    # --- Generate labels ---
    labels = get_protocol_labels(protocol, nc)
    if len(labels) != nc:
        labels = [f"C{i+1}" for i in range(nc)]

    # --- Extract per-fly per-cycle trajectories ---
    flies = []
    for fi in range(n_flies):
        x_all = all_fly_x[fi]
        y_all = all_fly_y[fi]
        first_frame = all_first_frame[fi]

        cycles = []
        for ci in range(nc):
            f_start = int(on_times[ci]) - first_frame
            f_end = int(off_times[ci]) - first_frame

            if f_start < 0:
                f_start = 0
            if f_end > len(x_all):
                f_end = len(x_all)

            if f_start >= f_end or f_start >= len(x_all):
                cycles.append([[], []])
                continue

            xc_fly = np.round(x_all[f_start:f_end], 1)
            yc_fly = np.round(y_all[f_start:f_end], 1)

            xc_list = [None if np.isnan(v) else v for v in xc_fly.tolist()]
            yc_list = [None if np.isnan(v) else v for v in yc_fly.tolist()]

            cycles.append([xc_list, yc_list])

        flies.append({"i": fi + 1, "c": cycles})

    result = {
        "xc": round(xc, 1),
        "yc": round(yc, 1),
        "r": round(r, 1),
        "nc": nc,
        "lp": led_patterns,
        "tp": training_patterns,
        "lb": labels,
        "flies": flies,
    }

    print(f"    {exp_name}: {n_flies} flies, {nc} cycles")
    return exp_name, result


def extract_protocol(analysis_dir, protocol):
    """Extract all experiments for one protocol. Returns dict."""
    prot_dir = os.path.join(analysis_dir, protocol)
    if not os.path.isdir(prot_dir):
        print(f"  {protocol}: directory not found, skipping")
        return {}

    all_dirs = sorted(os.listdir(prot_dir))
    exp_dirs = [d for d in all_dirs if os.path.isdir(os.path.join(prot_dir, d)) and "_Rig" in d]

    if not exp_dirs:
        print(f"  {protocol}: no experiments found")
        return {}

    print(f"  {protocol}: {len(exp_dirs)} experiments")
    protocol_data = {}

    for exp_name in exp_dirs:
        exp_path = os.path.join(prot_dir, exp_name)
        result = extract_experiment(exp_path, protocol)
        if result is not None:
            name, data = result
            protocol_data[name] = data

    return protocol_data


def save_protocol_json(protocol, data, output_dir):
    """Save protocol JSON, merging with existing data."""
    json_path = os.path.join(output_dir, f"{protocol}.json")

    existing = {}
    if os.path.isfile(json_path):
        with open(json_path, "r") as f:
            existing = json.load(f)

    existing.update(data)

    with open(json_path, "w") as f:
        json.dump(existing, f, separators=(",", ":"))

    size_mb = os.path.getsize(json_path) / (1024 * 1024)
    print(f"    Saved {json_path} ({size_mb:.1f} MB, {len(existing)} experiments)")
    return len(existing), sum(len(v["flies"]) for v in existing.values()), size_mb


def update_manifest(output_dir, protocol, n_exp, n_flies, size_mb):
    """Update manifest.json with protocol stats."""
    manifest_path = os.path.join(output_dir, "manifest.json")
    manifest = {}
    if os.path.isfile(manifest_path):
        with open(manifest_path, "r") as f:
            manifest = json.load(f)

    manifest[protocol] = {
        "n_exp": n_exp,
        "n_flies": n_flies,
        "size_mb": round(size_mb, 1),
    }

    manifest = dict(sorted(manifest.items()))

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)


def update_html_dropdown(output_dir, protocols_in_manifest):
    """Update the <select> dropdown in index.html to include all protocols."""
    html_path = os.path.join(output_dir, "index.html")
    if not os.path.isfile(html_path):
        print("  WARNING: index.html not found, skipping dropdown update")
        return

    with open(html_path, "r") as f:
        html = f.read()

    select_pattern = re.compile(
        r'(<select[^>]*id="sel-prot"[^>]*>)(.*?)(</select>)',
        re.DOTALL,
    )
    match = select_pattern.search(html)
    if not match:
        print("  WARNING: could not find protSel <select> in index.html")
        return

    sorted_prots = sorted(protocols_in_manifest)
    options = "\n".join(
        f'      <option value="{p}">{p}</option>' for p in sorted_prots
    )
    new_select = f"{match.group(1)}\n{options}\n    {match.group(3)}"

    html = html[: match.start()] + new_select + html[match.end() :]

    with open(html_path, "w") as f:
        f.write(html)

    print(f"  Updated index.html dropdown: {sorted_prots}")


def discover_all_protocols(analysis_dir):
    """Find all protocol directories that have at least one experiment with trx.mat."""
    protocols = []
    for d in sorted(os.listdir(analysis_dir)):
        if not re.match(r"^P\d+$", d):
            continue
        prot_path = os.path.join(analysis_dir, d)
        if not os.path.isdir(prot_path):
            continue
        for sub in os.listdir(prot_path):
            if "_Rig" in sub and os.path.isfile(os.path.join(prot_path, sub, "trx.mat")):
                protocols.append(d)
                break
    return protocols


def main():
    parser = argparse.ArgumentParser(description="Extract trajectory data for dashboard")
    parser.add_argument("protocols", nargs="*", help="Protocol names (e.g., P023 P024)")
    parser.add_argument("--all", action="store_true", help="Process all protocols")
    parser.add_argument(
        "--analysis-dir",
        default=DEFAULT_ANALYSIS_DIR,
        help=f"Analysis data root (default: {DEFAULT_ANALYSIS_DIR})",
    )
    parser.add_argument(
        "--output-dir",
        default=str(SCRIPT_DIR),
        help=f"Output directory for JSON files (default: {SCRIPT_DIR})",
    )
    args = parser.parse_args()

    if args.all:
        protocols = discover_all_protocols(args.analysis_dir)
        print(f"Discovered {len(protocols)} protocols: {protocols}")
    elif args.protocols:
        protocols = [p.upper() for p in args.protocols]
    else:
        parser.print_help()
        sys.exit(1)

    if not protocols:
        print("No protocols to process.")
        sys.exit(0)

    print(f"\nAnalysis dir: {args.analysis_dir}")
    print(f"Output dir:   {args.output_dir}\n")

    for protocol in protocols:
        data = extract_protocol(args.analysis_dir, protocol)
        if data:
            n_exp, n_flies, size_mb = save_protocol_json(
                protocol, data, args.output_dir
            )
            update_manifest(args.output_dir, protocol, n_exp, n_flies, size_mb)
        else:
            print(f"  {protocol}: no data extracted")

    # Update HTML dropdown with all protocols in manifest
    manifest_path = os.path.join(args.output_dir, "manifest.json")
    if os.path.isfile(manifest_path):
        with open(manifest_path, "r") as f:
            manifest = json.load(f)
        update_html_dropdown(args.output_dir, list(manifest.keys()))

    print("\nDone.")


if __name__ == "__main__":
    main()
