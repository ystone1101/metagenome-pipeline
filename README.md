# A Robust Metagenome Shotgun Sequencing Analysis Pipeline

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

## Overview

This project provides a robust, sequential processing pipeline for shotgun metagenome sequencing data. It automates the key steps of quality control, host DNA removal, and taxonomic classification using a combination of standard, powerful bioinformatics tools.

The entire pipeline is built as a modular Bash script, designed to be fault-tolerant, easy to configure, and reproducible. It leverages Conda environments to resolve complex software dependency issues, ensuring stability and portability across different systems.

## Pipeline Workflow

The pipeline processes each sample through the following major steps:

```
RAW DATA (.fastq.gz)
       │
       └─ (decompress_fastq) ─> Uncompressed FASTQ files
                                      │
                                      └─ (run_kneaddata) ─> Cleaned, host-removed reads (.fastq.gz)
                                                               │
                                                               ├─ (run_kraken2) ─> Taxonomic Classification
                                                               │
                                                               └─ (Copy & Cleanup)
                                                                       │
                                                                       ▼
                                                                FINAL RESULTS
```

## Key Features

-   **Modular Design**: Clear separation of configuration (`config`), functions (`lib`), and execution logic (`main`), making the code easy to read, modify, and maintain.
-   **Robust Error Handling**: The script stops immediately on any command failure (`set -euo pipefail`) and provides a detailed, colored error report using a `trap` handler.
-   **Conda Environment Integration**: Solves dependency conflicts by running `KneadData` and `Kraken2`/`krakentools` in separate, dedicated Conda environments via the `conda run` command.
-   **Checkpointing**: Automatically detects previously processed samples in the temporary working directory (`WORK_DIR`) to avoid re-running `KneadData`, saving significant time on pipeline restarts.
-   **Efficient Disk Usage**: Cleans up large, uncompressed temporary files as soon as they are no longer needed, minimizing the peak disk space required.
-   **Clear & Stable Logging**: A custom logging system provides colored, timestamped messages to the console for easy monitoring, while saving a complete, plain-text log to a file for detailed records. This system is designed to be stable and avoid terminal hanging issues.

## Prerequisites

### 1. Software
This pipeline relies on **Conda** for environment management. You must have Anaconda or Miniconda installed.

### 2. Databases
You must download and build the necessary databases before running the pipeline:
-   A **host reference database** for `KneadData` (e.g., human genome), indexed with `bowtie2`.
-   A **taxonomic database** for `Kraken2`.

## Installation & Setup

#### Step 1: Clone the Repository
```bash
git clone [https://github.com/ystone1101/metagenome-pipeline.git](https://github.com/ystone1101/metagenome-pipeline.git)
cd metagenome-pipeline
```

#### Step 2: Create Conda Environments
Run the following commands to create the required environments. The names (`KneadData`, `kraken_env`) must match those in the `config.sh` file.

```bash
# Create the KneadData environment
conda create -n KneadData python=3.7 -y
conda activate KneadData
conda install -c bioconda kneaddata fastqc -y
conda deactivate

# Create the Kraken environment
conda create -n kraken_env python=3.8 -y
conda activate kraken_env
conda install -c bioconda kraken2 -y
pip install krakentools
conda deactivate
```

#### Step 3: Configure the Pipeline
Open `config/pipeline_config.sh` with a text editor and modify the variables to match your system. **Pay close attention to the following:**

| Variable | Description | Example |
| :--- | :--- | :--- |
| `USER_HOME` | Your home directory path. | `/home/kys` |
| `KNEADDATA_ENV`| Name of the Conda env for KneadData. | `KneadData` |
| `KRAKEN_ENV` | Name of the Conda env for Kraken2/tools. | `kraken_env` |
| `DB_PATH` | Full path to your KneadData reference db. | `${USER_HOME}/Desktop/Database/human/hg38` |
| `KRAKEN_DB` | Full path to your Kraken2 database. | `${USER_HOME}/Desktop/Database/kraken2_db2` |
| `RAW_DIR` | Full path to your raw `.fastq.gz` files. | `/media/sf_H_DRIVE/GDM/raw` |
| `CLEAN_DIR` | Final archival directory for cleaned reads. | `/media/sf_D_DRIVE/GDM/QC` |
| `BASE_DIR`| Parent directory for most analysis outputs. | `${USER_HOME}/Desktop/GDM`|

## Usage

1.  **Prepare Input Data**
    Place your paired-end FASTQ files (e.g., `sampleA_1.fastq.gz`, `sampleA_2.fastq.gz`) in the `RAW_DIR` you specified in the config file.

2.  **Grant Execute Permissions**
    This only needs to be done once.
    ```bash
    chmod +x main_pipeline.sh
    ```

3.  **Run the Pipeline**
    Execute the main script from the project's root directory:
    ```bash
    ./main_pipeline.sh
    ```
    The pipeline will then process each sample sequentially.

## Output Structure

Upon completion, you can find the results in the directories specified in your `config.sh` file:

-   `$CLEAN_DIR/`: Final, cleaned (host-removed) FASTQ files for long-term storage.
-   `$CLEAN_DIR/fastqc_reports/`: Contains `pre_kneaddata` and `post_kneaddata` subdirectories with FastQC reports.
-   `$BASE_DIR/kraken2/`: Raw Kraken2 output and report files.
-   `$BASE_DIR/mpa/`: Taxonomic profiles in MetaPhlAn format, generated from Kraken2 reports.
-   `$BASE_DIR/kneaddata_logs/`: Detailed logs from each `KneadData` run, useful for debugging.
-   `$BASE_DIR/pipeline_*.log`: The main log file for the entire pipeline run.
-   `$BASE_DIR/kraken2_summary.tsv`: A summary table of classification statistics for all samples.

## Future Work

This repository is planned to be expanded with additional analysis pipelines that run after `main_pipeline.sh`:

-   **`diversity_pipeline.sh`**: To calculate alpha and beta diversity metrics using QIIME 2.
-   **`figure_pipeline.sh`**: To generate publication-quality figures and visualizations using R/ggplot2.

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
