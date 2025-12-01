<p align="center">
  <img src="https://github.com/user-attachments/assets/77e2d0ab-47d6-489f-a728-2da9cdf7af16" alt="Dokkaebi Pipeline Banner" width="300"/>
</p>

# Dokkaebi Metagenome Pipeline

![GitHub stars](https://img.shields.io/github/stars/your-username/your-repo-name?style=social)
![GitHub forks](https://img.shields.io/github/forks/your-username/your-repo-name?style=social)
![GitHub last commit](https://img.shields.io/github/last-commit/your-username/your-repo-name)
![Made with Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-v1.0.0-blue.svg)](https://github.com/your-username/your-repo-name/releases/tag/v1.0.0)

**Dokkaebi (도깨비)** is a powerful and automated pipeline for recovering high-quality Metagenome-Assembled Genomes (MAGs) from shotgun metagenome sequencing data. From preprocessing raw reads to the final annotation of MAGs, it integrates a complex analysis process into a single command, providing a reproducible and efficient workflow.

***

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Pipeline Workflow](#pipeline-workflow)
- [Prerequisites](#prerequisites)
- [Installation & Setup](#installation--setup)
- [Usage](#usage)
- [Stopping the Pipeline](#stopping-the-pipeline)
- [Output Structure](#output-structure)
- [Future Work](#future-work)
- [License](#license)

***

## Overview

Metagenome analysis is inherently challenging due to the complexity of data processing, the vast number of tools involved, and the need to handle massive datasets over long runtimes. **Dokkaebi** is designed to solve these problems by providing a powerful, automated, and reproducible workflow.

To maximize efficiency and stability, Dokkaebi implements a **"Continuous Monitoring"** system that automatically detects and processes new files, along with a **"Hybrid Parallel Strategy"** that runs I/O-bound tasks in parallel while managing memory-heavy tasks sequentially.

Users can select their desired depth of analysis through three flexible modes—`qc` (preprocessing and taxonomic profiling), `mag` (MAG recovery and analysis), and `all` (the entire workflow). With sophisticated error handling and checkpointing features, the pipeline ensures reliable performance and allows for safe resumption of analysis during large-scale data processing.

***

## Key Features

- **🔄 Continuous Monitoring & Auto-Scaling**: The pipeline runs in an infinite loop, instantly detecting new FASTQ files using ultra-fast `stat` checks (0.1s latency). It automatically prioritizes QC for new samples before starting the time-consuming MAG analysis.
- **⚡ Hybrid Parallel Processing**:
    - **QC Step**: Runs `pigz` decompression and `KneadData` in **parallel (default: 4 jobs)** to saturate CPU usage.
    - **Taxonomy Step**: Automatically switches to **serial execution** for memory-intensive tools like `Kraken2` using a lock system to prevent OOM errors.
    - **Annotation Step**: Runs `Bakta` on multiple MAGs simultaneously to speed up the final stage.
- **🛡️ Smart Error Handling & Resume**:
    - **Retry Logic**: Transient errors don't stop the pipeline. It retries up to 2 times before logging a critical error and moving on.
    - **Graceful Shutdown**: Stops safely only after completing the current batch of jobs when a signal file is detected.
- **✨ All-in-One Workflow**: Flexibly execute the pipeline using `qc`, `mag`, and `all` commands.
- **🧪 Built-in Test Mode**: Verify all dependencies with `dokkaebi mag --test`.
***

## Pipeline Workflow

1.  **Monitoring**: Watches the input directory for changes.
2.  **QC Phase (Parallel)**:
    * Decompression (`pigz`)
    * QC & Host Removal (`KneadData` or `fastp`) -> **Runs 4 samples at once.**
    * Taxonomic Profiling (`Kraken2` / `Bracken`) -> **Runs 1 sample at a time (Safe Mode).**
3.  **Stability Check**: Re-scans the input directory. If new files arrive, it repeats QC immediately.
4.  **MAG Phase (Batch)**:
    * Assembly (`MEGAHIT`)
    * Binning & Refinement (`MetaWRAP`)
    * Taxonomy (`GTDB-Tk`)
    * Annotation (`Bakta`) -> **Runs 6 MAGs at once.**
5.  **Reporting**: Updates the HTML summary report.
6.  **Sleep & Repeat**: Sleeps for 10 minutes (configurable) to save CPU, then checks for new files again.

***


## Prerequisites

1.  **Conda**: Anaconda or Miniconda.
2.  **System Tools**: `pigz` (required for parallel decompression).
3.  **Databases**:
      - **Host reference database**: Indexed with `bowtie2` (for KneadData).
      - **Kraken2 database**: Standard or custom DB.
      - **GTDB-Tk database**: Release 214 or later.
      - **Bakta database**: Full or light version.

-----

## Installation & Setup

#### Step 1: Clone the Repository

```bash
git clone [https://github.com/ystone1101/metagenome-pipeline.git](https://github.com/ystone1101/metagenome-pipeline.git)
cd metagenome-pipeline
```

#### Step 2: Create Conda Environments

<details>
<summary><b>➡️ Click here to see Conda environment setup commands</b></summary>


The pipeline runs in several independent Conda environments. Create the required environments using the commands below. (The environment names must match those specified in the `config/*.sh` files.)

```bash
# Create environments for each tool (examples)
conda create -n KneadData_env -c bioconda kneaddata -y
conda create -n kraken_env -c bioconda kraken2 bracken -y
conda create -n fastp_env -c bioconda fastp -y
conda create -n megahit_env -c bioconda megahit -y
conda create -n metawrap_env -c bioconda metawrap-mg -y
conda create -n gtdbtk_env -c bioconda gtdbtk -y
conda create -n bakta_env -c bioconda bakta -y
# ... and other necessary tools (bbmap, samtools, etc.)
```

</details>

#### Step 3: Grant Execute Permissions

Grant execute permissions to all execution scripts.

```bash
chmod +x dokkaebi
chmod +x scripts/*.sh
```

*(Assuming `dokkaebi` is the renamed `dokkaebi.txt` file.)*

-----

## Usage

The Dokkaebi pipeline provides an intuitive command-line interface. All configurations are passed via command-line options.
The pipeline is designed to run in the background (e.g., using tmux or nohup).

#### General Syntax

`dokkaebi <command> <mode> [options...]`

  - **Commands**: `qc`, `mag`, `all`
  - **Modes**:
      - `qc` command: `host` or `environmental`
      - `mag` command: `all`, `megahit`, `metawrap`, `post-process`

#### Example 1: `qc` - Host-associated samples

```bash
./dokkaebi qc host \
    --input_dir /path/to/raw_reads \
    --output_dir /path/to/qc_output \
    --host_db /path/to/host_db \
    --kraken2_db /path/to/kraken2_db \
    --threads 16
```

#### Example 2: `mag` - Run MAG analysis on cleaned reads

```bash
./dokkaebi mag all \
    --input_dir /path/to/qc_output/01_clean_reads \
    --output_dir /path/to/mag_output \
    --gtdbtk_db_dir /path/to/gtdbtk_db \
    --bakta_db_dir /path/to/bakta_db \
    --kraken2_db /path/to/kraken2_db \
    --threads 16 \
    --memory_gb 100
```

#### Example 3: `all` - Run the entire workflow

```bash
./dokkaebi all host \
    --input_dir /data/project/raw_reads \
    --output_dir /data/project/results \
    --host_db /data/DB/host/hg38 \
    --kraken2_db /data/DB/kraken2 \
    --gtdbtk_db /data/DB/gtdbtk \
    --bakta_db /data/DB/bakta \
    --threads 48 \
    --memory_gb 120
```

#### Example 4: Running the Automated Test

To verify that all dependencies, environments, and databases are correctly configured for the MAG pipeline, you can run the built-in test mode. This will download a small public test dataset and run the complete MAG workflow on it. Note that paths to the main databases are still required to run the test.

```bash
./dokkaebi mag --test \
    --gtdbtk_db_dir /path/to/gtdbtk_db \
    --bakta_db_dir /path/to/bakta_db \
    --kraken2_db /path/to/kraken2_db
```

#### Example 4: Stopping the Pipeline
Since the pipeline runs in an infinite loop, you must use a Graceful Shutdown signal to stop it safely without corrupting data.

**Do not press ```Ctrl+C``` if analysis is running!** Instead:
1.  Open a new terminal.
2.  Create a file named ```stop_pipeline``` in your **input directory**.

```bash
#Example
touch /data/project/raw_reads/stop_pipeline
```

3.  The pipeline will detect this file after the current cycle finishes, perform cleanup, and exit cleanly.

-----


## Output Structure

When the `all` command is executed, the specified output directory will have the following structure:

```
<your_output_dir>/
├── 1_microbiome_taxonomy/      # QC and taxonomic analysis results
│   ├── 01_clean_reads/         # QC-completed FASTQ files
│   ├── 02_kraken2/             # Raw Kraken2 results
│   ├── 03_bracken/             # Raw Bracken results
│   ├── 05_bracken_merged/      # Merged Bracken result tables for all samples
│   ├── logs/                   # Detailed logs from KneadData/fastp
│   └── kraken2_summary.tsv     # Summary of Kraken2 classification statistics
│
└── 2_mag_analysis/             # MAG analysis results
    ├── 01_assembly/            # Assembly results for each sample (Contigs)
    ├── 05_metawrap/            # MetaWRAP binning and refinement results
    ├── 06_gtdbtk_on_mags/      # GTDB-Tk classification results for final MAGs
    ├── 07_bakta_on_mags/       # Bakta functional annotation results for final MAGs
    └── 3_mag_per_sample_*.log  # Main log file for the MAG pipeline
```

-----

## Future Work

  - **Pangenome Analysis**: Add a pangenome analysis pipeline using `Roary` or `PPanGGOLiN`.
  - **Metabolic Pathway Analysis**: Add a metabolic pathway reconstruction pipeline using `KEGG` or `MetaCyc` databases.
  - **Visualization**: Develop an interactive results visualization dashboard using `R/Shiny` or `Python/Dash`.

-----

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.

