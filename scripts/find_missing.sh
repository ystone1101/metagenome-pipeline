#!/bin/bash

# ==============================================================================
# 설정
# ==============================================================================
BASE_DIR="$1"

if [[ -z "$BASE_DIR" ]]; then
    echo "Usage: find_missing.sh <base_dir>"
    exit 1
fi

OUTPUT_LIST="${BASE_DIR}/missing_list.txt"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== 🕵️‍♂️ Missing Samples Detective (Safe Mode) ===${NC}"

# 1. QC 완료 명단 (후보군)
# _paired_1.fastq.gz 파일에서 순수 ID만 추출
find "${BASE_DIR}/1_microbiome_taxonomy" -name "*_paired_1.fastq.gz" \
| sed 's/.*\///' | sed 's/_paired_1.fastq.gz//' | sed -E 's/(_1|_2|_R1|_R2|_kneaddata).*//g' | sort > temp_qc.txt

QC_COUNT=$(cat temp_qc.txt | wc -l)

# 2. Taxonomy 완료 명단
# _S.bracken 파일에서 순수 ID만 추출
find "${BASE_DIR}/1_microbiome_taxonomy" -name "*_S.bracken" \
| sed 's/.*\///' | sed -E 's/(_S|_G|_F|_species)\.bracken//g' | sort > temp_tax.txt

# 3. 1차 후보군 추출 (QC는 있는데 Tax는 없는 것)
comm -23 temp_qc.txt temp_tax.txt > temp_candidates.txt

CANDIDATE_COUNT=$(cat temp_candidates.txt | wc -l)

if [ "$CANDIDATE_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ Perfect! All samples have Bracken results.${NC}"
    rm -f "$OUTPUT_LIST" temp_qc.txt temp_tax.txt temp_candidates.txt
    exit 0
fi

# ==============================================================================
# 4. [중요] 실행 중(Running)인 프로세스 확인 (안전장치)
# ==============================================================================
echo -e "${YELLOW}🔍 Verifying if candidates are currently running...${NC}"

# 현재 돌고 있는 Kraken2/Bracken 프로세스 목록 가져오기
CURRENT_PROCS=$(ps -ef | grep -E "kraken2|bracken" | grep -v "grep")

# 최종 명단 파일 초기화
> "$OUTPUT_LIST"

REAL_MISSING_COUNT=0

while read -r SAMPLE_ID; do
    # 내 ID가 현재 프로세스 목록에 포함되어 있는가?
    if echo "$CURRENT_PROCS" | grep -q "$SAMPLE_ID"; then
        # 실행 중이면 명단에서 제외!
        echo -e "   🏃 ${YELLOW}Skipping $SAMPLE_ID (Currently Running)${NC}"
    else
        # 실행 중도 아니고 결과도 없으면 -> 진짜 누락!
        echo "$SAMPLE_ID" >> "$OUTPUT_LIST"
        ((REAL_MISSING_COUNT++))
    fi
done < temp_candidates.txt

# ==============================================================================
# 5. 결과 리포트
# ==============================================================================
echo "----------------------------------------------------"
if [ "$REAL_MISSING_COUNT" -gt 0 ]; then
    echo -e "${RED}⚠️  Confirmed $REAL_MISSING_COUNT samples are DEAD/MISSING.${NC}"
    echo "📄 Safe List saved to: $OUTPUT_LIST"
    echo "   (These samples are safe to re-run)"
else
    echo -e "${GREEN}🎉 No dead samples found. (Others are still running)${NC}"
    rm -f "$OUTPUT_LIST"
fi

# 청소
rm temp_qc.txt temp_tax.txt temp_candidates.txt