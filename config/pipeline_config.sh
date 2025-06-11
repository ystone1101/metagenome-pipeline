#!/bin/bash
#=========================
# 환경 설정 변수 정의
# 이 파일은 파이프라인의 모든 주요 설정 값을 정의합니다.
# main_pipeline.sh에서 'source' 명령어로 로드됩니다.
#=========================

# --- ANSI Color Codes ---
# 터미널 로그 출력에 사용할 색상 코드를 정의합니다.
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color (색상 초기화)

# --- Conda 가상환경 이름 ---
# kneaddata 도구가 설치된 메인 환경
KNEADDATA_ENV="KneadData" 
# 의존성 충돌을 피하기 위해 kraken2, krakentools, bracken 등  별도로 설치한 환경
KRAKEN_ENV="kraken_env"

# 사용자 홈 디렉토리 경로 (⚠️ 여러분의 실제 경로로 반드시 수정하세요!)
# 예: /home/your_username 또는 /Users/your_username
USER_HOME="/home/kys" # <<--- 이 부분을 여러분의 홈 디렉토리로 변경!

# 스레드 설정 (도구별 분리)
KNEADDATA_THREADS=8 # KneadData (및 내부의 FastQC)에서 사용할 CPU 스레드 수
KRAKEN2_THREADS=8   # Kraken2에서 사용할 CPU 스레드 수

# 메모리 및 Trimmomatic 설정
KNEADDATA_MAX_MEMORY="85000m" # KneadData에 할당할 최대 메모리 (예: 80GB)
# 변수에는 Trimmomatic 옵션의 '값'만 저장합니다.
TRIMMOMATIC_OPTIONS="SLIDINGWINDOW:4:20 MINLEN:90" # Trimmomatic 옵션

# 데이터베이스 경로
# 호스트 유전체 데이터베이스 (KneadData용)
DB_PATH="${USER_HOME}/Desktop/Database/human/hg38" # <<--- 이 경로를 변경!
# Kraken2 분류 데이터베이스
KRAKEN_DB="${USER_HOME}/Desktop/Database/kraken2_db2" # <<--- 이 경로를 변경!

# 기본 작업 디렉토리
# 모든 파이프라인 결과물이 저장될 상위 디렉토리
BASE_DIR="${USER_HOME}/Desktop/GDM" # <<--- 이 경로를 변경하거나 유지!

# 세부 데이터 및 결과물 디렉토리
# 원본 FASTQ.gz 파일이 있는 디렉토리
# (외장 하드 또는 네트워크 드라이브 경로가 될 수 있습니다)
RAW_DIR="/media/sf_H_DRIVE/GDM/raw" # <<--- 원본 데이터 경로를 변경!

# 임시 작업 디렉토리
WORK_DIR="${BASE_DIR}/kneaddata_tmp"

# Kraken2 분석 결과 저장 디렉토리
KRAKEN_OUT="${BASE_DIR}/kraken2"

# MetaPhlAn 형식 보고서 저장 디렉토리
MPA_OUT="${BASE_DIR}/mpa"

# 정제된 FASTQ.gz 파일의 최종 저장 디렉토리 (최종 보관용)
# (외장 하드 또는 네트워크 드라이브 경로가 될 수 있음)
CLEAN_DIR="/media/sf_D_DRIVE/GDM/QC" # <<--- QC된 데이터 저장 경로를 변경!

# 모든 FastQC 보고서의 상위 디렉토리
FASTQC_REPORTS_DIR="${CLEAN_DIR}/fastqc_reports"

# KneadData 처리 전 FastQC 보고서 저장 디렉토리
FASTQC_PRE_KNEADDATA_DIR="${FASTQC_REPORTS_DIR}/pre_kneaddata"

# KneadData 처리 후 FastQC 보고서 저장 디렉토리
FASTQC_POST_KNEADDATA_DIR="${FASTQC_REPORTS_DIR}/post_kneaddata"

# 파이프라인 요약 및 전체 로그 파일 설정
# KneadData 관련 로그 파일 저장 디렉토리
KNEADDATA_LOG="${BASE_DIR}/kneaddata_logs"

# Kraken2 분류 요약 통계 파일
SUMMARY_TSV="${BASE_DIR}/kraken2_summary.tsv"

# 페어링 불일치 샘플 목록 파일
MISMATCH_FILE="${BASE_DIR}/mismatched_ids.txt"
