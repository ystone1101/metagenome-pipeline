#!/bin/bash
#================================================
# CONFIG FOR PIPELINE 2: PER-SAMPLE MAG ANALYSIS
#================================================

# --- Conda Virtual Environment Names ---
BBMAP_ENV="bbmap_env"
MEGAHIT_ENV="megahit_env"
METAWRAP_ENV="metawrap_env"
KRAKEN_ENV="kraken_env"
GTDBTK_ENV="gtdbtk_env"
BAKTA_ENV="bakta_env"

# --- Main Input Directory ---
# 1단계 파이프라인의 QC 완료 파일이 있는 폴더
#QC_READS_DIR="${CLEAN_DIR}"

# --- Main Output Directory for this pipeline ---
#MAG_BASE_DIR="${BASE_DIR}/MAG_analysis"

# --- Sub-directories for each step ---
REPAIR_DIR="${MAG_BASE_DIR}/00_repaired_reads"
ASSEMBLY_DIR="${MAG_BASE_DIR}/01_assembly"
ASSEMBLY_STATS_DIR="${MAG_BASE_DIR}/02_assembly_stats"
KRAKEN_ON_CONTIGS_DIR="${MAG_BASE_DIR}/03_kraken_on_contigs"
BAKTA_ON_CONTIGS_DIR="${MAG_BASE_DIR}/04_bakta_on_contigs"
METAWRAP_DIR="${MAG_BASE_DIR}/05_metawrap"
GTDBTK_ON_MAGS_DIR="${MAG_BASE_DIR}/06_gtdbtk_on_mags"
BAKTA_ON_MAGS_DIR="${MAG_BASE_DIR}/07_bakta_on_mags"
