# A Robust Metagenome Shotgun Sequencing Analysis Pipeline

This project provides a robust, sequential processing pipeline for shotgun metagenome data. It automates quality control, host DNA removal, and taxonomic classification using a combination of standard bioinformatics tools. The pipeline is designed to be modular, fault-tolerant, and easy to configure.

## Key Features

-   **Modular Design**: Clear separation of configuration (`config`), functions (`lib`), and execution logic (`main`).
-   **Robust Error Handling**: The script stops immediately on any command failure and provides a detailed error report.
-   **Conda Environment Integration**: Solves dependency conflicts by running tools like `KneadData` and `Kraken2`/`krakentools` in separate, dedicated Conda environments.
-   **Checkpointing**: Automatically detects previously processed samples in the temporary working directory (`WORK_DIR`) to avoid re-running `KneadData`, saving significant time on restarts.
-   **Efficient Disk Usage**: Cleans up large temporary files as soon as they are no longer needed within each sample's analysis.
-   **Clear Logging**: Provides colored, timestamped logs on the console for easy monitoring, while saving a complete, plain-text log to a file for detailed records.

## Prerequisites

### Software
This pipeline relies on `conda` for environment management. You must have Anaconda or Miniconda installed. The following tools are required:

1.  **In the `KneadData` environment:**
    -   `kneaddata`
    -   `fastqc`
2.  **In the `kraken_env` environment:**
    -   `kraken2`
    -   `krakentools` (for `kreport2mpa.py`)
3.  **System-level tools (usually pre-installed on Linux):**
    -   `pigz`
    -   `bash`, `sed`, `awk`, `grep`, `cut`, `cp`, `mv`, `rm`

### Databases
You must download and build the necessary databases before running the pipeline:
1.  A **host reference database** for `KneadData` (e.g., human genome), indexed with `bowtie2`.
2.  A **taxonomic database** for `Kraken2`.

## Setup

1.  **Clone the Repository**
    ```bash
    git clone [https://github.com/your_username/your_pipeline_repo.git](https://github.com/your_username/your_pipeline_repo.git)
    cd your_pipeline_repo
    ```

2.  **Create Conda Environments**
    Run the following commands to create the required environments. The names must match those in the `config.sh` file.

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

3.  **Configure the Pipeline**
    Open `config/pipeline_config.sh` with a text editor and modify the variables to match your system. **Pay close attention to the following:**
    -   `USER_HOME`: Your home directory path.
    -   `KNEADDATA_ENV` & `KRAKEN_ENV`: The names of your conda environments if you used different names.
    -   `DB_PATH`: The full path to your KneadData reference database.
    -   `KRAKEN_DB`: The full path to your Kraken2 database.
    -   `RAW_DIR`: The full path to the directory containing your raw `.fastq.gz` files.
    -   `CLEAN_DIR`: The full path to the directory where final cleaned files will be archived.

## Usage

1.  **Grant Execute Permissions**
    This only needs to be done once.
    ```bash
    chmod +x main_pipeline.sh
    ```

2.  **Run the Pipeline**
    Make sure your raw paired-end FASTQ files (e.g., `sampleA_1.fastq.gz`, `sampleA_2.fastq.gz`) are in the `RAW_DIR` you specified in the config file. Then, execute the main script:
    ```bash
    ./main_pipeline.sh
    ```
    The pipeline will process each sample sequentially, and you will see colored `[INFO]` logs on your screen indicating the progress. A detailed log, including all commands run, will be saved in a timestamped file within your `BASE_DIR`.

## Output Structure

Upon completion, you can find the results in the directories specified in your `config.sh` file:

-   `$CLEAN_DIR/`: Final, cleaned (host-removed) FASTQ files for long-term storage.
-   `$CLEAN_DIR/fastqc_reports/`: Contains `pre_kneaddata` and `post_kneaddata` subdirectories with FastQC reports.
-   `$BASE_DIR/kraken2/`: Raw Kraken2 output and report files.
-   `$BASE_DIR/mpa/`: Taxonomic profiles in MetaPhlAn format.
-   `$BASE_DIR/kneaddata_logs/`: Detailed logs from each `KneadData` run.
-   `$BASE_DIR/kraken2_summary.tsv`: A summary table of classification statistics for all samples.

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
