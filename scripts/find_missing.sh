#!/bin/bash

# ==============================================================================
# Missing Samples Detective (Final Fix)
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

echo -e "${GREEN}=== 🕵️‍♂️ Missing Samples Detective (Final Fix) ===${NC}"

# 1. QC 완료 명단 (Clean Reads) 추출
# [핵심 수정] 파이프라인이 생성하는 긴 꼬리표들을 순서대로 정확히 제거합니다.
# 1순위: Host Mode 결과 (_1_kneaddata_paired_1.fastq.gz)
# 2순위: Env Mode 결과 (_fastp_1.fastq.gz)
# 3순위: 일반적인 형태 (_paired_1.fastq.gz)
find "${BASE_DIR}/1_microbiome_taxonomy" -name "*_paired_1.fastq.gz" -o -name "*_fastp_1.fastq.gz" \
| sed 's/.*\///' \
| sed 's/_1_kneaddata_paired_1\.fastq\.gz$//' \
| sed 's/_kneaddata_paired_1\.fastq\.gz$//' \
| sed 's/_fastp_1\.fastq\.gz$//' \
| sed 's/_paired_1\.fastq\.gz$//' \
| sort -u > temp_qc.txt

QC_COUNT=$(cat temp_qc.txt | wc -l)

# 2. Taxonomy 완료 명단 (Bracken Results) 추출
# _S.bracken, _species.bracken 등 다양한 패턴 처리
find "${BASE_DIR}/1_microbiome_taxonomy" -name "*.bracken" \
| sed 's/.*\///' \
| sed -E 's/(_S|_G|_F|_species)?\.bracken$//' \
| sort -u > temp_tax.txt

TAX_COUNT=$(cat temp_tax.txt | wc -l)

# 3. 진짜 누락된 샘플 찾기 (QC에는 있는데 Tax에는 없는 것)
comm -23 temp_qc.txt temp_tax.txt > temp_candidates.txt

CANDIDATE_COUNT=$(cat temp_candidates.txt | wc -l)

# 4. 결과 리포트
if [ "$CANDIDATE_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ Perfect! All $QC_COUNT samples are analyzed.${NC}"
    rm -f "$OUTPUT_LIST" temp_qc.txt temp_tax.txt temp_candidates.txt
    exit 0
else
    # 실행 중인 프로세스 확인
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
        echo "   (QC Count: $QC_COUNT / Tax Count: $TAX_COUNT)"
    else
        echo -e "${GREEN}🎉 No dead samples found. (Others are running)${NC}"
        rm -f "$OUTPUT_LIST"
    fi
fi

# 임시 파일 청소
rm -f temp_qc.txt temp_tax.txt temp_candidates.txt