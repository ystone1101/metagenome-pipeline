#!/bin/bash

# ==============================================================================
# 설정
# ==============================================================================
# 실행할 때 받은 인자를 변수로 사용합니다.
BASE_DIR="$1"
KRAKEN_DB="$2"
THREADS="$3"

# 인자가 없으면 에러 처리
if [[ -z "$BASE_DIR" || -z "$KRAKEN_DB" ]]; then
    echo "❌ Usage: auto_repair.sh <output_dir> <kraken_db> <threads>"
    exit 1
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT_DIR=$(dirname "$SCRIPT_DIR")

# [핵심] qc.sh와 똑같이 설정 파일($KRAKEN_ENV 등)을 불러옵니다.
if [ -f "${PROJECT_ROOT_DIR}/config/pipeline_config.sh" ]; then
    source "${PROJECT_ROOT_DIR}/config/pipeline_config.sh"
else
    echo "Error: pipeline_config.sh not found."
    exit 1
fi

# 1. 탐정 스크립트 실행
# (여기서 안전한 명단 missing_list.txt가 생성됨)
bash "${SCRIPT_DIR}/find_missing.sh" "$BASE_DIR"

LIST_FILE="${BASE_DIR}/missing_list.txt"

if [ ! -f "$LIST_FILE" ] || [ ! -s "$LIST_FILE" ]; then
    echo "🎉 Nothing to repair."
    exit 0
fi

COUNT=$(cat "$LIST_FILE" | wc -l)

echo "----------------------------------------------------"
echo "🚑 Starting Repair for $COUNT samples..."
echo "----------------------------------------------------"
sleep 2 # 실수로 실행했다면 취소할 시간 2초

QC_BASE="${BASE_DIR}/1_microbiome_taxonomy"

while read -r SAMPLE_ID; do
    echo "▶ Repairing: $SAMPLE_ID"
    
    # [안전 삭제] 파일이 진짜 있을 때만 지우고 로그 남김
    if [ -f "${QC_BASE}/02_kraken_output/${SAMPLE_ID}.kraken2" ]; then
        echo "   Creating clean state (removing incomplete output)..."
        rm -f "${QC_BASE}/02_kraken_output/${SAMPLE_ID}.kraken2"
        rm -f "${QC_BASE}/02_kraken_output/${SAMPLE_ID}.output"
        rm -f "${QC_BASE}/02_kraken_output/${SAMPLE_ID}.report"
    fi
    
    # ... (이후 Kraken2 실행 로직은 동일) ...
    # [입력 파일 찾기]
    INPUT_R1=$(find "${QC_BASE}" -name "${SAMPLE_ID}*_paired_1.fastq.gz" | head -n 1)
    INPUT_R2=$(echo "$INPUT_R1" | sed 's/_paired_1.fastq.gz/_paired_2.fastq.gz/')
    
    if [ -z "$INPUT_R1" ]; then
        echo "   ❌ Error: Input file not found for $SAMPLE_ID"
        continue
    fi

    # [Kraken2 실행]
    OUT_DIR="${QC_BASE}/02_kraken_output"
    mkdir -p "$OUT_DIR"
    
    echo "   Running Kraken2..."
    conda run -n "$KRAKEN_ENV" kraken2 \
        --db "$KRAKEN_DB" \
        --threads "$THREADS" \
        --report "${OUT_DIR}/${SAMPLE_ID}.report" \
        --paired \
        --report-minimizer-data \
        --minimum-hit-groups 3 \
        "$INPUT_R1" "$INPUT_R2" > "${OUT_DIR}/${SAMPLE_ID}.output" 2> /dev/null
    
    # [Bracken 실행]
    if [ $? -eq 0 ]; then
        BRACKEN_OUT="${QC_BASE}/04_bracken_output"
        mkdir -p "$BRACKEN_OUT"
        
        # Bracken도 qc.sh 설정값($BRACKEN_READ_LEN, $BRACKEN_THRESHOLD) 사용
        # 단, 복구 스크립트에서는 보통 Species(S) 레벨만 복구하거나 루프를 돌림.
        # 여기서는 가장 중요한 'S' 레벨 복구
        echo "   Running Bracken..."
        conda run -n "$KRAKEN_ENV" bracken \
            -d "$KRAKEN_DB" \
            -i "${OUT_DIR}/${SAMPLE_ID}.report" \
            -o "${BRACKEN_OUT}/${SAMPLE_ID}.bracken" \
            -r "${BRACKEN_READ_LEN:-100}" \
            -l S \
            -t "${BRACKEN_THRESHOLD:-10}" # qc.sh는 threshold를 사용함 (-t는 스레드가 아님)
            
        echo "   ✅ Success: $SAMPLE_ID restored!"
    else
        echo "   💥 Failed: Kraken2 error on $SAMPLE_ID"
    fi

done < "$LIST_FILE"

# 작업 끝난 명단은 삭제 (혹은 주석 처리해서 보관)
rm "$LIST_FILE"
echo "----------------------------------------------------"
echo "✨ Auto-repair completed."