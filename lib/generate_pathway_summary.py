#!/usr/bin/env python3
"""
Aggregate per-gene read-mapping coverage (BBMap pileup.sh outorf=) with
EggNOG-mapper gene annotations (KEGG_Pathway / CAZy columns) into a
sample x pathway abundance table.

Usage:
    generate_pathway_summary.py \
        --eggnog_dir  <MAG_BASE_DIR>/04_eggnog_on_contigs \
        --coverage_dir <MAG_BASE_DIR>/08_gene_coverage \
        --output_dir  <MAG_BASE_DIR>/09_functional_pathways

Expects, for each sample <S>:
    <eggnog_dir>/<S>/<S>.emapper.annotations
    <coverage_dir>/<S>/<S>_gene_coverage.tsv   (BBMap pileup.sh outorf= output)

No third-party libraries required (stdlib only), so this can run inside
any environment that has python3 (the pipeline runs it inside eggnog_env).
"""
import argparse
import csv
import glob
import os
import sys
from collections import defaultdict

# Column-name based lookup so this survives minor BBMap/EggNOG version
# differences in exact header wording/ordering.
COVERAGE_ID_HINTS = ("id",)
COVERAGE_VALUE_HINTS = ("avg_fold", "fold", "cov", "depth")


def find_column(header, hints):
    header_lower = [h.lower() for h in header]
    for hint in hints:
        for i, col in enumerate(header_lower):
            if hint in col:
                return i
    return None


def load_gene_coverage(path):
    """Returns {gene_id: coverage_float}."""
    coverage = {}
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return coverage
    with open(path) as fh:
        header = None
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            if line.startswith("#"):
                header = line.lstrip("#").split("\t")
                continue
            if header is None:
                # No header seen yet; can't reliably parse. Bail on this file.
                print(f"[WARN] {path}: no header line found, skipping file.", file=sys.stderr)
                return {}
            fields = line.split("\t")
            id_idx = find_column(header, COVERAGE_ID_HINTS)
            val_idx = find_column(header, COVERAGE_VALUE_HINTS)
            if id_idx is None or val_idx is None:
                print(
                    f"[WARN] {path}: could not find ID/coverage columns in header {header}. "
                    "Check that BBMap's pileup.sh output format matches expectations.",
                    file=sys.stderr,
                )
                return {}
            if id_idx >= len(fields) or val_idx >= len(fields):
                continue
            gene_id = fields[id_idx].strip()
            try:
                value = float(fields[val_idx])
            except ValueError:
                continue
            coverage[gene_id] = value
    return coverage


def load_gene_annotations(path):
    """Returns {gene_id: {"KEGG_Pathway": [...], "CAZy": [...]}}."""
    annotations = {}
    if not os.path.isfile(path):
        return annotations
    with open(path) as fh:
        header = None
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            if line.startswith("#"):
                # emapper's real column header line starts with "#query"
                if line.lstrip("#").split("\t")[0].strip().lower() == "query":
                    header = line.lstrip("#").split("\t")
                continue
            if header is None:
                continue
            fields = line.split("\t")
            row = dict(zip(header, fields))
            gene_id = row.get("query", "").strip()
            if not gene_id:
                continue
            entry = {}
            for col in ("KEGG_Pathway", "CAZy"):
                raw = row.get(col, "-")
                if not raw or raw == "-":
                    entry[col] = []
                else:
                    entry[col] = [x.strip() for x in raw.split(",") if x.strip() and x.strip() != "-"]
            annotations[gene_id] = entry
    return annotations


def aggregate_sample(coverage, annotations, category):
    """Sum per-gene coverage grouped by pathway/CAZy family for one sample."""
    totals = defaultdict(float)
    for gene_id, cov in coverage.items():
        entry = annotations.get(gene_id)
        if not entry:
            continue
        for term in entry.get(category, []):
            totals[term] += cov
    return totals


def normalize_to_cpm(totals):
    grand_total = sum(totals.values())
    if grand_total <= 0:
        return {k: 0.0 for k in totals}
    return {k: (v / grand_total) * 1_000_000 for k, v in totals.items()}


def write_wide_table(per_sample_values, out_path, row_label):
    all_terms = sorted({term for values in per_sample_values.values() for term in values})
    samples = sorted(per_sample_values.keys())
    with open(out_path, "w", newline="") as fh:
        writer = csv.writer(fh, delimiter="\t")
        writer.writerow([row_label] + samples)
        for term in all_terms:
            writer.writerow([term] + [f"{per_sample_values[s].get(term, 0.0):.4f}" for s in samples])
    print(f"[INFO] Wrote {out_path} ({len(all_terms)} rows x {len(samples)} samples)")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--eggnog_dir", required=True)
    ap.add_argument("--coverage_dir", required=True)
    ap.add_argument("--output_dir", required=True)
    args = ap.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    sample_dirs = sorted(
        d for d in glob.glob(os.path.join(args.coverage_dir, "*")) if os.path.isdir(d)
    )
    if not sample_dirs:
        print(f"[WARN] No sample subfolders found under {args.coverage_dir}. Nothing to do.", file=sys.stderr)
        return

    pathway_abundance = {}
    cazy_abundance = {}

    for sample_dir in sample_dirs:
        sample = os.path.basename(sample_dir)
        coverage_file = os.path.join(sample_dir, f"{sample}_gene_coverage.tsv")
        annotation_file = os.path.join(args.eggnog_dir, sample, f"{sample}.emapper.annotations")

        coverage = load_gene_coverage(coverage_file)
        annotations = load_gene_annotations(annotation_file)

        if not coverage or not annotations:
            print(f"[WARN] {sample}: missing coverage or annotation data, skipping.", file=sys.stderr)
            continue

        pathway_totals = aggregate_sample(coverage, annotations, "KEGG_Pathway")
        cazy_totals = aggregate_sample(coverage, annotations, "CAZy")

        pathway_abundance[sample] = normalize_to_cpm(pathway_totals)
        cazy_abundance[sample] = normalize_to_cpm(cazy_totals)
        print(f"[INFO] {sample}: {len(pathway_totals)} KEGG pathways, {len(cazy_totals)} CAZy families.")

    if pathway_abundance:
        write_wide_table(
            pathway_abundance,
            os.path.join(args.output_dir, "kegg_pathway_summary.tsv"),
            "KEGG_Pathway",
        )
    if cazy_abundance:
        write_wide_table(
            cazy_abundance,
            os.path.join(args.output_dir, "cazy_summary.tsv"),
            "CAZy",
        )


if __name__ == "__main__":
    main()
