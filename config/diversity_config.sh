#!/bin/bash
# CONFIG FOR PIPELINE 1: DIVERSITY ANALYSIS (Alpha/Beta on Bracken output)
# qc.sh 안에서 $BASE_DIR(QC 파이프라인 출력 폴더)가 정의된 뒤에 source 됩니다.

# --- Conda Environment Name (kraken_env에 krakentools가 포함되어 있음) ---
KRAKEN_ENV="kraken_env"

# --- Input Directory (qc.sh의 Bracken 개별 결과 폴더와 일치해야 함) ---
BRACKEN_DIR="${BASE_DIR}/03_bracken"

# --- Output Directory ---
DIVERSITY_OUT_BASE="${BASE_DIR}/07_diversity_analysis"

# --- 분석 대상 taxonomic level(들). BRACKEN_LEVELS(pipeline_config.sh)의 부분집합이어야 함 ---
DIVERSITY_LEVELS="S"

# --- Alpha Diversity Indices ---
# BP: Berger-Parker, Sh: Shannon, F: Fisher, Si: Simpson's, ISi: Inverse Simpson
ALPHA_DIVERSITY_INDICES="BP Sh F Si ISi"
