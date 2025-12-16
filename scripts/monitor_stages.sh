#!/bin/bash

# ==============================================================================
# 1. 설정
# ==============================================================================
BASE_DIR="/data/CDC_2024ER110301/results"
RAW_DATA_DIR="/data/CDC_2024ER110301/raw_data"
REFRESH_RATE=30

# ==============================================================================
# 2. 색상 및 유틸리티
# ==============================================================================
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[1;31m'  # 밝은 빨강
GRAY='\033[1;30m'
NC='\033[0m'

# ==============================================================================
# ✨ [NEW] 스타일리시한 진행바 그리기 함수
# ==============================================================================
draw_bar() {
    local current=$1
    local total=$2
    local width=30  # 바의 길이 (취향껏 조절 가능: 20~50 추천)

    # 0으로 나누기 방지 및 퍼센트 계산
    if [ "$total" -le 0 ]; then total=1; fi
    local percent=$(( (current * 100) / total ))
    if [ "$percent" -gt 100 ]; then percent=100; fi

    # 채워질 블록 개수 계산
    local num_full=$(( (current * width) / total ))
    
    # --- 스타일 설정 (여기서 모양을 바꿀 수 있어요!) ---
    local full_char="█"    # 꽉 찬 블록 문자
    local empty_char="▒"   # 빈 블록 문자 (또는 '░', '─' 등)
    
    # 색상 설정 (기본: 초록색 / 완료 시: 파란색 / 0%: 회색)
    local bar_color="$GREEN"
    local text_color="$CYAN"
    local end_emoji=""

    if [ "$percent" -eq 100 ]; then
        bar_color="$BLUE"      # 100% 달성 시 색상 변경
        text_color="$GREEN"
        end_emoji=" 🎉"        # 축하 이모지 추가
    elif [ "$percent" -eq 0 ]; then
        bar_color="$GRAY"      # 0% 일 때 색상
    fi

    # --- 그리기 시작 (printf 사용으로 정교한 제어) ---
    # 1. 여는 괄호
    printf "${GRAY}[${NC}"
    
    # 2. 꽉 찬 부분 그리기 (색상 적용)
    printf "%b" "$bar_color"
    for ((i=0; i<num_full; i++)); do printf "%s" "$full_char"; done
    
    # 3. 빈 부분 그리기 (회색 적용)
    printf "%b" "$GRAY"
    for ((i=num_full; i<width; i++)); do printf "%s" "$empty_char"; done
    
    # 4. 닫는 괄호 및 색상 초기화
    printf "%b${GRAY}]${NC} " "$NC"

    # 5. 퍼센트 및 정보 출력 (오른쪽 정렬로 깔끔하게)
    printf "%b%3d%% (%d/%d)%b%s\n" "$text_color" "$percent" "$current" "$total" "$NC" "$end_emoji"
}

# ==============================================================================
# 3. 메인 루프
# ==============================================================================
while true; do
    clear
    echo -e "${BLUE}##############################################################${NC}"
    echo -e "${BLUE}#    👹 Dokkaebi Pipeline - Monitor V10 (Zombie Detector)    #${NC}"
    echo -e "${BLUE}##############################################################${NC}"
    echo " Time: $(date '+%H:%M:%S')"
    echo "--------------------------------------------------------------"

    # [1] 전체 샘플 수
    if [ -d "$RAW_DATA_DIR" ]; then
        TOTAL_SAMPLES=$(find "$RAW_DATA_DIR" -maxdepth 1 -name "*.fastq.gz" | sed 's/.*\///' | sed -E 's/(_1|_2|_R1|_R2)\.fastq\.gz//g' | sed 's/\.fastq\.gz//g' | sort | uniq | wc -l)
    else
        TOTAL_SAMPLES=0
    fi
    echo -e "${CYAN}Total Unique Samples: $TOTAL_SAMPLES ${NC}"
    echo "--------------------------------------------------------------"

    # [2] QC
    QC_BASE="${BASE_DIR}/1_microbiome_taxonomy"
    if [ -d "$QC_BASE" ]; then
        COUNT_QC=$(find "$QC_BASE" -name "*_paired_1.fastq.gz" | wc -l)
        echo -e " 1. Reads QC (KneadData)"
        draw_bar $COUNT_QC $TOTAL_SAMPLES
        # QC Running: 프로세스 기반
        RUNNING_QC=$(ps -ef | grep "kneaddata" | grep -v "grep" | grep -v "kraken" | grep -o "KGDM[^ /]*" | sed -E 's/(_1|_2|_R1|_R2|_kneaddata).*//g' | sort | uniq | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
        if [ -n "$RUNNING_QC" ]; then
            echo -e "   └─ 🏃 Running: ${CYAN}${RUNNING_QC}${NC}"
        fi
    else
        echo -e " 1. Reads QC: ${GRAY}Folder Not Found (Pending)${NC}"
    fi
    echo ""

    # [3] Taxonomy (Kraken2/Bracken) --> [여기가 핵심!]
    if [ -d "$QC_BASE" ]; then
        # 1. 완료 카운트
        COUNT_TAX=$(find "$QC_BASE" -name "*_S.bracken" 2>/dev/null | wc -l)
        if [ "$COUNT_TAX" -eq 0 ]; then
             COUNT_TAX=$(find "$QC_BASE" -name "*.bracken" | sed 's/.*\///' | sed -E 's/(_S|_G|_F|_species)\.bracken//g' | sort | uniq | wc -l)
        fi
        
        echo -e " 2. Taxonomy (Kraken2/Bracken)"
        draw_bar $COUNT_TAX $TOTAL_SAMPLES
        
        # 2. Running vs Stalled 구분 로직
        # A: Started Files
        find "$QC_BASE" -name "*.kraken2" -o -name "*.output" | sed 's/.*\///' | sed 's/\.kraken2//' | sed 's/\.output//' | sort | uniq > /tmp/mon_start.txt
        # B: Finished Files
        find "$QC_BASE" -name "*.bracken" | sed 's/.*\///' | sed -E 's/(_S|_G|_F|_species)\.bracken//g' | sed 's/\.bracken//g' | sort | uniq > /tmp/mon_end.txt
        
        # C: Candidates (Running or Stalled)
        comm -23 /tmp/mon_start.txt /tmp/mon_end.txt > /tmp/mon_candidates.txt
        
        ACTIVE_LIST=""
        STALLED_LIST=""
        
        # 현재 실행 중인 Kraken 프로세스 덤프
        CURRENT_PROCS=$(ps -ef | grep "kraken2" | grep -v "grep")
        
        if [ -s /tmp/mon_candidates.txt ]; then
            while read -r SAMPLE_ID; do
                # 후보 ID가 현재 프로세스 목록에 있는가?
                if echo "$CURRENT_PROCS" | grep -q "$SAMPLE_ID"; then
                    ACTIVE_LIST+="${SAMPLE_ID}, "
                else
                    STALLED_LIST+="${SAMPLE_ID}, "
                fi
            done < /tmp/mon_candidates.txt
        fi

        # 출력 정리
        if [ -n "$ACTIVE_LIST" ]; then
            ACTIVE_LIST=$(echo "$ACTIVE_LIST" | sed 's/, $//')
            echo -e "   └─ 🏃 Running: ${CYAN}${ACTIVE_LIST}${NC}"
        fi
        
        if [ -n "$STALLED_LIST" ]; then
            STALLED_LIST=$(echo "$STALLED_LIST" | sed 's/, $//')
            echo -e "   └─ ⚠️  ${RED}Stalled/Failed: ${STALLED_LIST} (Need Repair!)${NC}"
        fi
        
        if [ -z "$ACTIVE_LIST" ] && [ -z "$STALLED_LIST" ]; then
             echo -e "   └─ 💤 Idle (대기 중)"
        fi
        
        rm /tmp/mon_start.txt /tmp/mon_end.txt /tmp/mon_candidates.txt
    else
        echo -e " 2. Taxonomy: ${GRAY}Folder Not Found (Pending)${NC}"
    fi
    echo ""

    # [4] Assembly
    MAG_BASE="${BASE_DIR}/2_mag_analysis"
    ASM_DIR=$(find "$MAG_BASE" -type d -name "*assembly*" 2>/dev/null | head -n 1)
    if [ -n "$ASM_DIR" ]; then
        COUNT_ASM=$(find "$MAG_BASE" -name "final.contigs.fa" 2>/dev/null | wc -l)
        echo -e " 3. Assembly (MEGAHIT) ${RED}<-- Bottleneck${NC}"
        draw_bar $COUNT_ASM $TOTAL_SAMPLES
        # Assembly Running Check
        RUNNING_ASM=$(find "$ASM_DIR" -mindepth 1 -maxdepth 1 -type d ! -exec test -e "{}/final.contigs.fa" \; -print | wc -l)
        if [ "$RUNNING_ASM" -gt 0 ]; then
             echo -e "   └─ 🏃 Running: ${CYAN}${RUNNING_ASM} samples assembling...${NC}"
        fi
    else
        echo -e " 3. Assembly: ${GRAY}Folder Not Found (Pending)${NC}"
    fi
    echo ""

    # [5] Binning & Annotation
    GTDB_DIR=$(find "$MAG_BASE" -type d -name "*gtdb*" 2>/dev/null | head -n 1)
    if [ -n "$GTDB_DIR" ]; then
        COUNT_MAG=$(find "$MAG_BASE" -name "gtdbtk.*.summary.tsv" 2>/dev/null | wc -l)
        echo -e " 4. Binning & MAGs (GTDB-Tk)"
        draw_bar $COUNT_MAG $TOTAL_SAMPLES
    else
        echo -e " 4. Binning: ${GRAY}Folder Not Found (Pending)${NC}"
    fi
    echo ""

    BAKTA_DIR=$(find "$MAG_BASE" -type d -name "*bakta*" 2>/dev/null | head -n 1)
    if [ -n "$BAKTA_DIR" ]; then
        COUNT_FUNC=$(find "$MAG_BASE" -name "*.gff3" 2>/dev/null | wc -l)
        echo -e " 5. Annotation (Bakta)"
        draw_bar $COUNT_FUNC $TOTAL_SAMPLES
    else
        echo -e " 5. Annotation: ${GRAY}Folder Not Found (Pending)${NC}"
    fi

    echo "--------------------------------------------------------------"
    echo " [Ctrl+C] to exit"
    sleep $REFRESH_RATE
done