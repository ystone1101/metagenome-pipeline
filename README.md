# A Robust Metagenome Analysis Pipeline

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A robust, sequential processing pipeline for shotgun metagenome sequencing data. This pipeline automates quality control, host DNA removal, and taxonomic classification using a combination of standard bioinformatics tools, all wrapped in a clear and maintainable Bash script.

It is designed with stability and reproducibility in mind, leveraging Conda environments to manage complex software dependencies.

## Table of Contents

-   [Overview](#overview)
-   [Key Features](#key-features)
-   [Pipeline Workflow](#pipeline-workflow)
-   [Prerequisites](#prerequisites)
-   [Installation & Setup](#installation--setup)
-   [Usage](#usage)
-   [Output Structure](#output-structure)
-   [Future Work](#future-work)
-   [License](#license)
-   [Contact](#contact)

## Overview

This project was created to provide a simple yet powerful command-line tool for the initial processing of shotgun metagenomics data. The main goal is to offer a transparent, easy-to-use, and fault-tolerant workflow that handles the crucial first steps of analysis, from raw reads to a taxonomic profile, while ensuring reproducibility through Conda environments.

## Key Features

-   **⚙️ Modular Design**: Clear separation of configuration (`config`), functions (`lib`), and execution logic (`main`).
-   **🛡️ Robust Error Handling**: The script stops immediately on any command failure and provides a detailed error report.
-   **🌿 Conda Environment Integration**: Solves dependency conflicts by running `KneadData` and `Kraken2`/`krakentools` in separate, dedicated Conda environments.
-   **↪️ Checkpointing**: Automatically detects previously processed samples to avoid re-running `KneadData`, saving significant time on pipeline restarts.
-   **💾 Efficient Disk Usage**: Cleans up large, uncompressed temporary files as soon as they are no longer needed.
-   **📝 Clear & Stable Logging**: Provides colored logs to the console for easy monitoring and saves a complete, plain-text log to a file. The logging system is designed to be stable and avoid terminal hanging issues.

## Pipeline Workflow

The pipeline processes each sample through the following major steps:

```
Input Paired-End FASTQ files (.fastq.gz)
│
└─ Decompression (pigz)
   │
   └─ Quality Control & Host Removal (KneadData)
      │   ├─ Quality Trimming (Trimmomatic)
      │   └─ Host Read Filtering (Bowtie2)
      │
      └─ Cleaned Paired-End Reads (.fastq.gz)
         │
         └─ Taxonomic Classification (Kraken2)
            │   ├─ Classification & Reporting
            │   └─ MPA-style Report Generation (krakentools)
            │
            └─ Copy to Final Directory & Cleanup
                   │
                   ▼
            Final Analysis Results
```

## Prerequisites

1.  **Conda**: You must have Anaconda or Miniconda installed to manage the software environments.
2.  **Databases**: You must download and/or build the necessary databases before running the pipeline.
    -   A **host reference database** for `KneadData` (e.g., human genome hg38), indexed with `bowtie2`.
    -   A **taxonomic database** for `Kraken2`.

## Installation & Setup

#### Step 1: Clone the Repository

```bash
git clone https://github.com/ystone1101/metagenome-pipeline.git
cd metagenome-pipeline
```

#### Step 2: Create Conda Environments

Run the following commands to create the two required environments. The names (`KneadData`, `kraken_env`) must match those in the `config.sh` file.

```bash
# Create the KneadData environment
conda create -n KneadData python=3.7 -y
conda activate KneadData
conda install -c bioconda kneaddata -y
conda deactivate

# Create the Kraken environment
conda create -n kraken_env python=3.8 -y
conda activate kraken_env
conda install -c bioconda -c conda-forge kraken2 krakentools bracken r bowtie2 samtools -y
conda deactivate
```

#### Step 3: Configure the Pipeline

Open `config/pipeline_config.sh` with a text editor and modify the variables to match your system.

**Critical variables to check:**

| Variable | Description | Example |
| :--- | :--- | :--- |
| `KNEADDATA_ENV`| Name of the Conda env for KneadData. | `KneadData` |
| `KRAKEN_ENV` | Name of the Conda env for Kraken2. | `kraken_env` |
| `USER_HOME` | Your home directory path. | `/home/kys` |
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

```
<Your BASE_DIR>/
├── kneaddata_logs/         # Detailed logs from each KneadData run
├── kraken2/                # Raw Kraken2 output (.kraken2) and report (.k2report) files
├── mpa/                    # Taxonomic profiles in MetaPhlAn format
├── pipeline_*.log          # The main log file for the entire pipeline run
└── kraken2_summary.tsv     # Summary table of classification statistics

<Your CLEAN_DIR>/
├── fastqc_reports/         # Contains pre_kneaddata and post_kneaddata subdirectories
│   ├── pre_kneaddata/
│   └── post_kneaddata/
└── *.fastq.gz              # Final, cleaned (host-removed) FASTQ files for archival
```

## Future Work

This repository is planned to be expanded with additional analysis pipelines that run after `main_pipeline.sh`:

-   **`diversity_pipeline.sh`**: To calculate alpha and beta diversity metrics using QIIME 2.
-   **`figure_pipeline.sh`**: To generate publication-quality figures and visualizations using R/ggplot2.

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
