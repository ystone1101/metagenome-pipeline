# Docker Images for the Dokkaebi Pipeline

Each tool the pipeline calls via `conda run -n <env>` has a matching
Dockerfile here, built directly from the pinned `environments/*_env.yml`
files at the repo root. This keeps the containers byte-for-byte consistent
with the conda environments the pipeline (and the paper's results) were
actually run with.

## Layout

```
docker/
  kneaddata/Dockerfile
  fastp/Dockerfile
  kraken/Dockerfile
  bbmap/Dockerfile
  megahit/Dockerfile
  metawrap/Dockerfile
  gtdbtk/Dockerfile
  bakta/Dockerfile
  eggnog/Dockerfile
  build-all.sh
```

## Build context

Every Dockerfile does `COPY environments/<name>_env.yml /tmp/environment.yml`,
so it must be built with the **repository root** as build context, not the
`docker/<tool>/` directory itself:

```bash
docker build -f docker/kneaddata/Dockerfile -t dokkaebi/kneaddata:v1.0.0 .
```

Or build everything at once:

```bash
bash docker/build-all.sh v1.0.0
```

## Running a tool

Containers run with `conda run -n <env>` as the entrypoint, so you just pass
the tool's normal arguments:

```bash
docker run --rm -v "$PWD/data":/data dokkaebi/megahit:v1.0.0 \
    -1 /data/sample_1.fastq.gz -2 /data/sample_2.fastq.gz -o /data/assembly
```

## Databases (Kraken2, GTDB-Tk, Bakta, EggNOG)

Reference databases are large (tens of GB to >1 TB) and are **not** baked
into the images. Mount them as read-only volumes at runtime:

```bash
docker run --rm \
    -v /path/to/kraken2_db:/db:ro \
    -v "$PWD/data":/data \
    dokkaebi/kraken:v1.0.0 \
    --db /db --paired /data/sample_1.fastq.gz /data/sample_2.fastq.gz ...
```

GTDB-Tk additionally needs `GTDBTK_DATA_PATH` set to wherever you mount its
database (the conda env ships a placeholder value for this variable):

```bash
docker run --rm \
    -v /path/to/gtdbtk_db:/db:ro \
    -e GTDBTK_DATA_PATH=/db \
    -v "$PWD/data":/data \
    dokkaebi/gtdbtk:v1.0.0 \
    classify_wf --genome_dir /data/bins --out_dir /data/gtdbtk_out --cpus 8 -x fa
```

## Singularity / Apptainer (HPC)

If your cluster doesn't allow the Docker daemon, build once with Docker
(or on a machine that has it) and convert:

```bash
singularity build dokkaebi_megahit_v1.0.0.sif docker-daemon://dokkaebi/megahit:v1.0.0
# or, once images are pushed to a registry:
singularity build dokkaebi_megahit_v1.0.0.sif docker://<registry>/dokkaebi/megahit:v1.0.0
```

## Known reproducibility caveat: `metawrap_env`

`metawrap_env.yml` pulls packages from the `ursky` conda channel (the
original MetaWRAP author's personal channel, predating its bioconda
inclusion) and pins very old builds (Python 2.7, boost 1.64, etc.). This
environment is the most likely of the nine to eventually fail to solve if
upstream channels remove old package builds. Once `dokkaebi/metawrap` is
built successfully, **push it to a registry (or archive the built image)
immediately** rather than relying on being able to rebuild it later from
the `.yml` file alone.

## Verifying a build

```bash
docker run --rm dokkaebi/bakta:v1.0.0 bakta --version
```

Each image's `CMD` runs the tool's version check by default, so
`docker run --rm dokkaebi/<tool>:v1.0.0` with no extra args is a quick
smoke test after building.
