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

THREADS=20

SCRIPT_DIR="$(dirname "$0")"

# 1. 탐정 스크립트 실행
# (여기서 안전한 명단 missing_list.txt가 생성됨)
bash "${SCRIPT_DIR}/find_missing.sh"

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
    
    kraken2 --db "$KRAKEN_DB" --threads "$THREADS" \
        --report "${OUT_DIR}/${SAMPLE_ID}.report" \
        --paired "$INPUT_R1" "$INPUT_R2" > "${OUT_DIR}/${SAMPLE_ID}.output"
    
    # [Bracken 실행]
    if [ $? -eq 0 ]; then
        BRACKEN_OUT="${QC_BASE}/04_bracken_output"
        mkdir -p "$BRACKEN_OUT"
        
        bracken -d "$KRAKEN_DB" -i "${OUT_DIR}/${SAMPLE_ID}.report" \
            -o "${BRACKEN_OUT}/${SAMPLE_ID}.bracken" \
            -r 150 -l S -t "$THREADS"
        echo "   ✅ Success: $SAMPLE_ID restored!"
    else
        echo "   💥 Failed: Kraken2 error on $SAMPLE_ID"
    fi

done < "$LIST_FILE"

# 작업 끝난 명단은 삭제 (혹은 주석 처리해서 보관)
rm "$LIST_FILE"
echo "----------------------------------------------------"
echo "✨ Auto-repair completed."