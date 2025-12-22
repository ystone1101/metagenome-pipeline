#!/bin/bash

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

echo -e "${GREEN}=== 🕵️‍♂️ Missing Samples Detective (Fixed Mode) ===${NC}"

# 1. QC 완료 명단 (후보군) 추출
# [핵심 수정] '_1', '_2' 같은 숫자를 지우는 코드를 뺐습니다.
# 오직 '_paired_1.fastq.gz' 확장자만 깔끔하게 떼어냅니다.
find "${BASE_DIR}/1_microbiome_taxonomy" -name "*_paired_1.fastq.gz" \
| sed 's/.*\///' \
| sed 's/_paired_1\.fastq\.gz$//' \
| sort -u > temp_qc.txt

# 2. Taxonomy 완료 명단 추출
# [핵심 수정] '_S.bracken' 또는 그냥 '.bracken' 모두 인정합니다.
find "${BASE_DIR}/1_microbiome_taxonomy" -name "*.bracken" \
| sed 's/.*\///' \
| sed -E 's/(_S|_G|_F|_species)?\.bracken$//' \
| sort -u > temp_tax.txt

# 3. 진짜 누락된 샘플 찾기 (QC엔 있는데 Tax엔 없는 것)
comm -23 temp_qc.txt temp_tax.txt > temp_candidates.txt

CANDIDATE_COUNT=$(cat temp_candidates.txt | wc -l)

# 4. 결과 처리
if [ "$CANDIDATE_COUNT" -eq 0 ]; then
    # 정상! (대부분의 경우 여기서 종료될 것입니다)
    echo -e "${GREEN}✅ Perfect! All samples are analyzed.${NC}"
    rm -f "$OUTPUT_LIST" temp_qc.txt temp_tax.txt temp_candidates.txt
    exit 0
else
    # 혹시 진짜로 누락된 게 있는지, 아니면 실행 중인지 확인
    echo -e "${YELLOW}🔍 Verifying if candidates are currently running...${NC}"
    CURRENT_PROCS=$(ps -ef | grep -E "kraken2|bracken" | grep -v "grep")
    > "$OUTPUT_LIST"
    
    REAL_MISSING_COUNT=0
    while read -r SAMPLE_ID; do
        if echo "$CURRENT_PROCS" | grep -q "$SAMPLE_ID"; then
            echo -e "   🏃 ${YELLOW}Skipping $SAMPLE_ID (Running)${NC}"
        else
            echo "$SAMPLE_ID" >> "$OUTPUT_LIST"
            ((REAL_MISSING_COUNT++))
        fi
    done < temp_candidates.txt
    
    if [ "$REAL_MISSING_COUNT" -gt 0 ]; then
        echo -e "${RED}⚠️  Confirmed $REAL_MISSING_COUNT samples are DEAD/MISSING.${NC}"
        echo "📄 Safe List saved to: $OUTPUT_LIST"
    else
        echo -e "${GREEN}🎉 No dead samples found.${NC}"
        rm -f "$OUTPUT_LIST"
    fi
fi

rm -f temp_qc.txt temp_tax.txt temp_candidates.txt