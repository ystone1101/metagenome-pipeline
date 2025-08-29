<p align="center">
  <img src="https://github.com/user-attachments/assets/77e2d0ab-47d6-489f-a728-2da9cdf7af16" alt="Dokkaebi Pipeline Banner" width="750"/>
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
- [Output Structure](#output-structure)
- [Future Work](#future-work)
- [License](#license)

***

## Overview

Metagenome analysis can be challenging to reproduce due to the numerous tools and complex data processing steps involved. The Dokkaebi pipeline was designed to solve these problems. Through three modes—`qc` (preprocessing and taxonomic profiling), `mag` (MAG recovery and analysis), and `all` (the entire workflow)—users can select their desired depth of analysis. With sophisticated error handling and checkpointing features, it flexibly manages interruptions that may occur during large-scale data processing.

***

## Key Features

- **✨ All-in-One Workflow**: Flexibly execute the pipeline from raw reads to final annotated MAGs using the `qc`, `mag`, and `all` commands.
- **🛡️ Robust & Resumable**: All scripts stop immediately upon error (`set -euo pipefail`) and provide detailed error logs. Additionally, sophisticated checkpointing using per-step success flags (`.success`) and input file checksums (`.state`) allows for safe resumption of analysis from the point of interruption.
- **⚙️ Modular & Maintainable**: The structure, with a clear separation of functionalities (`scripts`), libraries (`lib`), and configurations (`config`), maximizes code readability and maintainability.
- **🧪 Built-in Test Mode**: The `dokkaebi mag --test` option allows for automatic verification of the pipeline's proper functioning and dependencies, ensuring the environment is correctly set up before running on real data.
- **🎨 User-Friendly Interface**: Each pipeline visually communicates its progress with colorful logs and ASCII art, and provides detailed help messages (`--help`) to enhance usability.
- **🌿 Isolated Conda Environments**: The tools required for each analysis step are run in independent Conda environments, fundamentally resolving dependency conflicts.

***

## Pipeline Workflow

```mermaid
graph TD
    subgraph Pipeline 1 - QC & Taxonomy
        A[Input FASTQ Files]
        --> B{QC & Host Removal}
        --> C[Cleaned Reads]
        --> D{Taxonomic Classification}
        --> E[Taxonomic Profiles]
    end

    C -- Cleaned Reads --> G

    subgraph Pipeline 2 - MAG Analysis
        G{De Novo Assembly}
        --> H[Contigs]
        --> I{Binning & Refinement}
        --> J[Refined Bins - MAGs]

        subgraph " "
            direction LR
            J --> K["Taxonomic Classification (GTDB-Tk)"]
            J --> M["Functional Annotation (Bakta)"]
        end

        K --> L[Final Annotated MAGs]
        M --> L
    end

    style " " fill:none,stroke:none
```
-----

## Prerequisites

1.  **Conda**: Anaconda or Miniconda must be installed.
2.  **Databases**: All necessary databases for the analysis must be downloaded and built beforehand.
      - **Host reference database**: A host genome for `KneadData` (e.g., human hg38), which needs to be indexed with `bowtie2`.
      - **Kraken2 database**: A classification database for `Kraken2` and `Bracken`.
      - **GTDB-Tk database**: The database for `GTDB-Tk`.
      - **Bakta database**: The database for `Bakta` (required).

-----

## Installation & Setup

#### Step 1: Clone the Repository

```bash
git clone https://github.com/ystone1101/metagenome-pipeline.git
cd metagenome-pipeline
```

#### Step 2: Create Conda Environments

```
\<details\>
\<summary\>\<b\>➡️ Click here to see Conda environment setup commands\</b\>\</summary\>
```

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

\</details\>

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
    --input_dir /path/to/raw_reads \
    --output_dir /path/to/project_output \
    --host_db /path/to/host_db \
    --kraken2_db /path/to/kraken2_db \
    --gtdbtk_db /path/to/gtdbtk_db \
    --bakta_db /path/to/bakta_db \
    --threads 16 \
    --memory_gb 100
```

#### Example 4: Running the Automated Test

To verify that all dependencies, environments, and databases are correctly configured for the MAG pipeline, you can run the built-in test mode. This will download a small public test dataset and run the complete MAG workflow on it. Note that paths to the main databases are still required to run the test.

```bash
./dokkaebi mag --test \
    --gtdbtk_db_dir /path/to/gtdbtk_db \
    --bakta_db_dir /path/to/bakta_db \
    --kraken2_db /path/to/kraken2_db
```
    
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

